require 'json'
require 'net/http'
require 'uri'
require 'capybara/dsl'
require_relative './version'

module PercyCapybara
  CLIENT_INFO = "percy-capybara/#{VERSION}".freeze
  ENV_INFO = "capybara/#{Capybara::VERSION} ruby/#{RUBY_VERSION}".freeze

  PERCY_DEBUG = ENV['PERCY_LOGLEVEL'] == 'debug'
  PERCY_SERVER_ADDRESS = ENV['PERCY_SERVER_ADDRESS'] || 'http://localhost:5338'
  PERCY_LABEL = "[\u001b[35m" + (PERCY_DEBUG ? 'percy:capybara' : 'percy') + "\u001b[39m]"

  private_constant :CLIENT_INFO
  private_constant :ENV_INFO

  UNSUPPORTED_IFRAME_SRCS = %w[
    about:blank about:srcdoc javascript: data: blob: vbscript: chrome: chrome-extension:
  ].freeze

  private_constant :UNSUPPORTED_IFRAME_SRCS

  # Take a DOM snapshot and post it to the snapshot endpoint
  def percy_snapshot(name, options = {})
    return unless percy_enabled?

    page = Capybara.current_session

    begin
      percy_dom_script = fetch_percy_dom
      page.evaluate_script(percy_dom_script)
      dom_snapshot = get_serialized_dom(page, options, percy_dom_script)
      page.evaluate_script(fetch_percy_dom)

      # Readiness gate -- runs before serialize when CLI supports it.
      # Uses evaluate_async_script with a callback signal so the SDK can block
      # on PercyDOM.waitForReady. In-browser typeof guard makes this a no-op on
      # older CLIs that lack waitForReady.
      readiness_diagnostics = wait_for_ready(page, options)

      # Merge .percy.yml config options with snapshot options (snapshot options take priority).
      # Deep merge with consistent string keys at all levels: nested Hashes merge
      # recursively, per-call wins at leaves, arrays/scalars replace.
      config_options = @cli_config&.dig('snapshot') || {}
      merged_options = deep_merge_options(config_options, deep_stringify(options))

      dom_snapshot = page
        .evaluate_script("(function() { return PercyDOM.serialize(#{merged_options.to_json}) })()")

      if readiness_diagnostics && dom_snapshot.is_a?(Hash)
        dom_snapshot['readiness_diagnostics'] = readiness_diagnostics
      end

      response = fetch('percy/snapshot',
        name: name,
        url: page.current_url,
        dom_snapshot: dom_snapshot,
        client_info: CLIENT_INFO,
        environment_info: ENV_INFO,
        **options,)

      data =
        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          log("Could not parse snapshot response for '#{name}': invalid JSON")
          if PERCY_DEBUG then log(e) end
          return
        end

      unless data['success']
        raise StandardError, data['error']
      end
    rescue StandardError => e
      log("Could not take DOM snapshot '#{name}'")

      if PERCY_DEBUG then log(e) end
    end
  end

  private def get_serialized_dom(page, options, percy_dom_script)
    dom_snapshot = page
      .evaluate_script("(function() { return PercyDOM.serialize(#{options.to_json}) })()")

    driver = page.driver.browser
    begin
      page_origin = get_origin(page.current_url)
      iframes = driver.find_elements(:tag_name, 'iframe')
      log("Found #{iframes.length} total iframe(s) on page") if PERCY_DEBUG

      processed_frames = []
      iframes.each do |frame|
        frame_src = frame.attribute('src')

        if unsupported_iframe_src?(frame_src)
          log("Skipping unsupported iframe src: #{frame_src}") if PERCY_DEBUG && frame_src
          next
        end

        begin
          frame_origin = get_origin(URI.join(page.current_url, frame_src).to_s)
        rescue StandardError => e
          log("Skipping iframe with invalid URL \"#{frame_src}\": #{e}") if PERCY_DEBUG
          next
        end

        if frame_origin == page_origin
          log("Skipping same-origin iframe: #{frame_src}") if PERCY_DEBUG
          next
        end

        # Pre-flight check: avoid the switch/serialize round-trip if there's no
        # data-percy-element-id, since process_frame would discard the snapshot
        # anyway and we'd silently waste a frame switch.
        unless frame.attribute('data-percy-element-id')
          log("Skipping iframe #{frame_src}: no data-percy-element-id found") if PERCY_DEBUG
          next
        end

        result = process_frame(driver, frame, options, percy_dom_script)
        processed_frames << result if result
      end

      if processed_frames.any?
        dom_snapshot['corsIframes'] = processed_frames
        log("Captured #{processed_frames.length} cross-origin iframe(s)")
      end
    rescue StandardError => e
      log("Failed to process cross-origin iframes: #{e}") if PERCY_DEBUG
      begin
        driver.switch_to.default_content
      rescue StandardError
        nil
      end
    end

    dom_snapshot
  end

  private def unsupported_iframe_src?(src)
    return true if src.nil? || src.empty?

    UNSUPPORTED_IFRAME_SRCS.any? { |prefix| src == prefix || src.start_with?(prefix) }
  end

  private def get_origin(url)
    uri = URI.parse(url)
    raise URI::InvalidURIError, "no host in #{url}" if uri.host.nil?

    default_ports = {'http' => 80, 'https' => 443}
    netloc = uri.host.to_s
    netloc += ":#{uri.port}" if uri.port && uri.port != default_ports[uri.scheme]
    "#{uri.scheme}://#{netloc}"
  end

  private def process_frame(driver, frame_element, options, percy_dom_script)
    frame_url = frame_element.attribute('src') || 'unknown-src'
    log("Processing cross-origin iframe: #{frame_url}") if PERCY_DEBUG

    begin
      driver.switch_to.frame(frame_element)
      begin
        driver.execute_script(percy_dom_script)
        iframe_options = options.merge('enableJavaScript' => true)
        iframe_snapshot =
          driver.execute_script("return PercyDOM.serialize(#{iframe_options.to_json})")
        log("Serialized cross-origin iframe: #{frame_url}") if PERCY_DEBUG
      rescue StandardError => e
        log("Failed to serialize cross-origin iframe #{frame_url}: #{e}") if PERCY_DEBUG
        return nil
      ensure
        begin
          driver.switch_to.default_content
        rescue StandardError
          begin
            driver.switch_to.parent_frame
          rescue StandardError
            nil
          end
        end
      end
    rescue StandardError => e
      log("Failed to switch to frame #{frame_url}: #{e}") if PERCY_DEBUG
      begin
        driver.switch_to.default_content
      rescue StandardError
        nil
      end
      return nil
    end

    percy_element_id = frame_element.attribute('data-percy-element-id')
    unless percy_element_id
      log("Skipping frame #{frame_url}: no data-percy-element-id found") if PERCY_DEBUG
      return nil
    end

    if PERCY_DEBUG
      log("Successfully captured cross-origin iframe: #{frame_url} " \
          "(percyElementId: #{percy_element_id})")
    end

    {
      'iframeData' => {'percyElementId' => percy_element_id},
      'iframeSnapshot' => iframe_snapshot,
      'frameUrl' => frame_url,
    }
  end

  # Determine if the Percy server is running, caching the result so it is only checked once
  private def percy_enabled?
    return @percy_enabled unless @percy_enabled.nil?

    begin
      response = fetch('percy/healthcheck')
      version = response['x-percy-core-version']

      if version.nil?
        log('You may be using @percy/agent ' \
            'which is no longer supported by this SDK. ' \
            'Please uninstall @percy/agent and install @percy/cli instead. ' \
            'https://www.browserstack.com/docs/percy/migration/migrate-to-cli')
        @percy_enabled = false
        return false
      end

      if version.split('.')[0] != '1'
        log("Unsupported Percy CLI version, #{version}")
        @percy_enabled = false
        return false
      end

      body = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      @cli_config = body['config'] || {}
      @percy_enabled = true
      true
    rescue StandardError => e
      log('Percy is not running, disabling snapshots')

      if PERCY_DEBUG then log(e) end
      @percy_enabled = false
      false
    end
  end

  # Fetch the @percy/dom script, caching the result so it is only fetched once
  private def fetch_percy_dom
    return @percy_dom unless @percy_dom.nil?

    response = fetch('percy/dom.js')
    @percy_dom = response.body
  end

  # Readiness gate: runs PercyDOM.waitForReady before serialize.
  #
  # Returns diagnostics to attach to the domSnapshot, or nil.
  # Config precedence: options[:readiness] / options['readiness'] > {} (the
  # CLI applies its balanced preset default when passed {}). preset='disabled'
  # skips the script entirely. Opt-in: only runs when the caller explicitly
  # passes a `readiness` option -- keeps non-opting tests insulated from
  # Capybara drivers that don't implement evaluate_async_script.
  # Any StandardError is caught at debug level.
  private def wait_for_ready(page, options)
    return nil unless options.key?(:readiness) || options.key?('readiness')

    readiness_config = options[:readiness] || options['readiness'] || {}
    return nil if readiness_config.is_a?(Hash) && (
      readiness_config[:preset] == 'disabled' || readiness_config['preset'] == 'disabled'
    )

    begin
      page.evaluate_async_script(<<~JS)
        var cfg = #{readiness_config.to_json};
        var done = arguments[arguments.length - 1];
        try {
          if (typeof PercyDOM !== 'undefined' && typeof PercyDOM.waitForReady === 'function') {
            PercyDOM.waitForReady(cfg).then(function(r){ done(r); }).catch(function(){ done(); });
          } else { done(); }
        } catch (e) { done(); }
      JS
    rescue StandardError => e
      if PERCY_DEBUG then log("waitForReady failed, proceeding to serialize: #{e}") end
      nil
    end
  end

  # Recursively stringify all Hash keys so per-call options match the
  # string-keyed config parsed from .percy.yml JSON at every nesting level.
  private def deep_stringify(obj)
    case obj
    when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
    when Array then obj.map { |e| deep_stringify(e) }
    else obj
    end
  end

  # Deep-merge two string-keyed Hashes: nested Hashes merge recursively,
  # per-call (override) wins at the leaves, arrays/scalars replace.
  private def deep_merge_options(base, override)
    base.merge(override) do |_key, old_val, new_val|
      old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge_options(old_val, new_val) : new_val
    end
  end

  private def log(msg)
    puts "#{PERCY_LABEL} #{msg}"
  end

  # Make an HTTP request (GET,POST) using Ruby's Net::HTTP. If `data` is present,
  # `fetch` will POST as JSON.
  private def fetch(url, data = nil)
    uri = URI("#{PERCY_SERVER_ADDRESS}/#{url}")

    response = if data
      Net::HTTP.post(uri, data.to_json)
    else
      Net::HTTP.get_response(uri)
    end

    unless response.is_a? Net::HTTPSuccess
      raise StandardError, "Failed with HTTP error code: #{response.code}"
    end

    response
  end
end

# Add the `percy_snapshot` method to the the Capybara session class
# `page.percy_snapshot('name', { options })`
Capybara::Session.class_eval { include PercyCapybara }
