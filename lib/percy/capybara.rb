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

  # Take a DOM snapshot and post it to the snapshot endpoint
  def percy_snapshot(name, options = {})
    return unless percy_enabled?

    page = Capybara.current_session

    begin
      page.evaluate_script(fetch_percy_dom)

      # Readiness gate -- runs before serialize when CLI supports it (PER-7348).
      # Uses evaluate_async_script with a callback signal so the SDK can block
      # on PercyDOM.waitForReady. In-browser typeof guard makes this a no-op on
      # older CLIs that lack waitForReady.
      readiness_diagnostics = wait_for_ready(page, options)

      dom_snapshot = page
        .evaluate_script("(function() { return PercyDOM.serialize(#{options.to_json}) })()")

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

      unless response.body.to_json['success']
        raise StandardError, data['error']
      end
    rescue StandardError => e
      log("Could not take DOM snapshot '#{name}'")

      if PERCY_DEBUG then log(e) end
    end
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

  # Readiness gate (PER-7348): runs PercyDOM.waitForReady before serialize.
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
