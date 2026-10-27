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

      # Single serialize pass -- get_serialized_dom serializes the page with the
      # merged options and attaches any captured cross-origin iframes.
      dom_snapshot = get_serialized_dom(page, merged_options, percy_dom_script)

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
    driver = selenium_browser(page)
    expose_closed_shadow_roots(driver, options) unless driver.nil?

    dom_snapshot = page
      .evaluate_script("(function() { return PercyDOM.serialize(#{options.to_json}) })()")

    return dom_snapshot if driver.nil?

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

  CHROMIUM_BROWSERS = %w[chrome chromium msedge microsoftedge chrome-headless-shell].freeze
  NON_CDP_BROWSERS = %w[firefox safari].freeze
  LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
  CLOSED_SHADOW_MAX_HOSTS = 200
  CLOSED_SHADOW_SET_FN = 'function(shadowRoot) { ' \
    'window.__percyClosedShadowRoots = window.__percyClosedShadowRoots || new WeakMap(); ' \
    'window.__percyClosedShadowRoots.set(this, shadowRoot); }'.freeze
  BIDI_SHADOW_CANDIDATES_FN = '(root) => { const out = []; ' \
    'const hostable = ' \
    '/^(article|aside|blockquote|body|div|footer|h[1-6]|header|main|nav|p|section|span)$/; ' \
    'const walk = (r) => { for (const e of r.querySelectorAll("*")) { ' \
    'if (e.shadowRoot) walk(e.shadowRoot); ' \
    'else if (e.localName.includes("-") || hostable.test(e.localName)) out.push(e); } }; ' \
    'walk(root || document); return out; }'.freeze
  BIDI_SHADOW_SET_FN = '(pairs) => { ' \
    'const m = window.__percyClosedShadowRoots = ' \
    'window.__percyClosedShadowRoots || new WeakMap(); ' \
    'for (const [h, s] of pairs) m.set(h, s); }'.freeze
  CLASSIC_SHADOW_CANDIDATES_JS = 'const out = []; ' \
    'const walk = (r) => { for (const e of r.querySelectorAll("*")) { ' \
    'if (e.shadowRoot) walk(e.shadowRoot); else if (e.localName.includes("-")) out.push(e); } }; ' \
    'walk(arguments[0] || document); return out;'.freeze
  CLASSIC_SHADOW_SET_JS = '(window.__percyClosedShadowRoots = ' \
    'window.__percyClosedShadowRoots || new WeakMap()).set(arguments[0], arguments[1]);'.freeze

  # Mirrors percy-selenium-ruby's expose_closed_shadow_roots (same strategies
  # and order) without depending on that gem. @percy/dom reads closed roots
  # from window.__percyClosedShadowRoots because page JS cannot reach them.
  private def expose_closed_shadow_roots(driver, options)
    return if options['disableShadowDOM'] || options[:disableShadowDOM]
    return if chromium_with_cdp?(driver) && expose_closed_shadow_roots_cdp(driver)
    return if bidi_session?(driver) && expose_closed_shadow_roots_bidi(driver)

    expose_closed_shadow_roots_classic(driver) if closed_shadow_classic_allowed?(driver)
  rescue StandardError => e
    log("Could not expose closed shadow roots: #{e}")
  end

  private def browser_name(driver)
    driver.capabilities.browser_name.to_s.downcase
  rescue StandardError
    ''
  end

  private def chromium_with_cdp?(driver)
    return false unless driver.respond_to?(:execute_cdp)

    name = browser_name(driver)
    CHROMIUM_BROWSERS.include?(name) || !NON_CDP_BROWSERS.include?(name)
  end

  # Only a session started with `webSocketUrl: true` has a BiDi socket.
  private def bidi_session?(driver)
    return false unless driver.respond_to?(:bidi) && driver.respond_to?(:capabilities)

    caps = driver.capabilities
    (caps[:web_socket_url] || caps['webSocketUrl']).is_a?(String)
  rescue StandardError
    false
  end

  private def expose_closed_shadow_roots_cdp(driver)
    driver.execute_cdp('DOM.enable')
    root = driver.execute_cdp('DOM.getDocument', depth: -1, pierce: true)&.dig('root')
    return false if root.nil?

    closed_shadow_pairs(root).each do |host_id, shadow_id|
      host = driver.execute_cdp('DOM.resolveNode', backendNodeId: host_id).dig('object', 'objectId')
      shadow = driver.execute_cdp('DOM.resolveNode', backendNodeId: shadow_id)
        .dig('object', 'objectId')
      next unless host && shadow

      driver.execute_cdp(
        'Runtime.callFunctionOn',
        functionDeclaration: CLOSED_SHADOW_SET_FN, objectId: host, arguments: [{objectId: shadow}],
      )
    end
    true
  rescue StandardError => e
    log("Could not expose closed shadow roots via CDP: #{e}") if PERCY_DEBUG
    false
  end

  # Child frame documents are skipped: their closed roots would need the
  # WeakMap in the frame's own realm.
  private def closed_shadow_pairs(node, pairs = [])
    return pairs if node.nil? || node['contentDocument']

    (node['shadowRoots'] || []).each do |shadow|
      if shadow['shadowRootType'] == 'closed'
        pairs << [node['backendNodeId'], shadow['backendNodeId']]
      end
      closed_shadow_pairs(shadow, pairs)
    end
    (node['children'] || []).each { |child| closed_shadow_pairs(child, pairs) }
    pairs
  end

  # Selenium Ruby has no typed script module, so this uses the raw BiDi command.
  private def expose_closed_shadow_roots_bidi(driver)
    context = driver.window_handle
    scopes = [nil]
    exposed = 0
    until scopes.empty?
      scope = scopes.shift
      args = scope ? [{sharedId: scope}] : []
      nodes = bidi_call_function(driver, context, BIDI_SHADOW_CANDIDATES_FN, args)['value'] || []
      pairs = nodes.map do |node|
        shadow = node.dig('value', 'shadowRoot')
        [node['sharedId'], shadow['sharedId']] if shadow && shadow.dig('value', 'mode') == 'closed'
      end.compact
      next if pairs.empty?

      refs = pairs.map do |host, shadow|
        {type: 'array', value: [{sharedId: host}, {sharedId: shadow}]}
      end
      bidi_call_function(driver, context, BIDI_SHADOW_SET_FN, [{type: 'array', value: refs}])
      exposed += pairs.length
      break if exposed >= closed_shadow_max_hosts

      scopes.concat(pairs.map(&:last))
    end
    true
  rescue StandardError => e
    log("Could not expose closed shadow roots via BiDi: #{e}") if PERCY_DEBUG
    false
  end

  private def bidi_call_function(driver, context, function, args)
    response = driver.bidi.send_cmd(
      'script.callFunction',
      functionDeclaration: function, awaitPromise: false, target: {context: context},
      arguments: args, resultOwnership: 'none',
      serializationOptions: {maxDomDepth: 0, includeShadowTree: 'all'},
    )
    unless response['type'] == 'success'
      raise StandardError, "script.callFunction #{response['type']}"
    end

    response['result'] || {}
  end

  # W3C Get Element Shadow Root returns closed roots too. It costs one round
  # trip per candidate, hence the cap and the local-only default.
  private def expose_closed_shadow_roots_classic(driver)
    max_hosts = closed_shadow_max_hosts
    checked = 0
    scopes = [nil]
    capped = false
    until scopes.empty? || capped
      hosts = driver.execute_script(CLASSIC_SHADOW_CANDIDATES_JS, scopes.shift) || []
      hosts.each do |host|
        capped = checked >= max_hosts
        break if capped

        checked += 1
        shadow = element_shadow_root(host)
        next if shadow.nil?

        driver.execute_script(CLASSIC_SHADOW_SET_JS, host, shadow)
        scopes << shadow
      end
    end
    return unless capped && PERCY_DEBUG

    log("Closed shadow root scan stopped at #{max_hosts} hosts (PERCY_CLOSED_SHADOW_MAX_HOSTS)")
  end

  # NoSuchShadowRoot means "not a host"; Safari answers null, which the
  # binding cannot wrap. Both mean skip.
  private def element_shadow_root(host)
    host.shadow_root
  rescue StandardError
    nil
  end

  private def closed_shadow_max_hosts
    value = Integer(ENV['PERCY_CLOSED_SHADOW_MAX_HOSTS'] || CLOSED_SHADOW_MAX_HOSTS)
    value > 0 ? value : CLOSED_SHADOW_MAX_HOSTS
  rescue ArgumentError, TypeError
    CLOSED_SHADOW_MAX_HOSTS
  end

  # Remote grids add a full round trip per candidate, so classic is opt-in there.
  private def closed_shadow_classic_allowed?(driver)
    return true if ENV['PERCY_CLOSED_SHADOW_CLASSIC'] == 'true'
    return true if LOCAL_HOSTS.include?(command_executor_host(driver))

    unless @closed_shadow_remote_logged
      @closed_shadow_remote_logged = true
      log('closed shadow roots skipped on remote session; start the session with ' \
          'webSocketUrl: true or set PERCY_CLOSED_SHADOW_CLASSIC=true')
    end
    false
  end

  private def command_executor_host(driver)
    return nil unless driver.respond_to?(:bridge, true)

    URI.parse(driver.send(:bridge).http.send(:server_url).to_s).hostname
  rescue StandardError
    nil
  end

  private def selenium_browser(page)
    driver = page.driver
    return nil unless driver.respond_to?(:browser)

    browser = driver.browser
    unless browser.respond_to?(:find_elements) && browser.respond_to?(:switch_to)
      log('Skipping cross-origin iframe capture: driver is not Selenium-backed') if PERCY_DEBUG
      return nil
    end

    browser
  rescue StandardError => e
    log("Skipping cross-origin iframe capture: #{e}") if PERCY_DEBUG
    nil
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
