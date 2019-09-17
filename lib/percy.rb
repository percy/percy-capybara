require 'logger'
require 'net/http'
require 'uri'
require 'json'
require 'environment'

module Percy
  # Takes a snapshot of the given page HTML and its assets.
  #
  # See https://docs.percy.io/v1/docs/configuration for detailed documentation on
  # snapshot options.
  #
  # @param [Capybara::Session] page The Capybara page to snapshot.
  # @param [Hash] options
  # @option options [String] :name A unique name for the current page that identifies
  #   it across builds. By default this is the URL of the page, but can be customized if the
  #   URL does not entirely identify the current state.
  # @option options [Array(Number)] :widths Widths, in pixels, that you'd like to capture for
  #   this snapshot.
  def self.snapshot(page, options = {})
    return unless self._is_agent_running?

    domSnapshot = self._make_dom_snapshot(page)
    return unless domSnapshot

    if !options.has_key?(:name)
      options[:name] = page.current_url
    end

    body = {
      url: page.current_url,
      domSnapshot: domSnapshot,
      clientInfo: Percy.client_info,
      environmentInfo: Percy.environment_info,
    }
    body = body.merge(self._keys_to_json(options))
    self._post_snapshot_to_agent(body)
  end

  private

  AGENT_HOST = 'localhost'
  # Technically, the port is configurable when you run the agent. One day we might want
  # to make the port configurable in this SDK as well.
  AGENT_PORT = 5338
  AGENT_JS_PATH= '/percy-agent.js'

  def self._logger
    unless defined?(@logger)
      @logger = Logger.new(STDOUT)
      @logger.formatter = proc do |_severity, _datetime, _progname, msg|
        "[percy] #{msg} \n"
      end
    end
    return @logger
  end

  def self._get_agent_js
    begin
      return Net::HTTP.get(AGENT_HOST, AGENT_JS_PATH, AGENT_PORT)
    rescue => e
      self._logger.error { "Could not load #{AGENT_JS_PATH}. Error: #{e}" }
      return nil
    end
  end

  def self._make_dom_snapshot(page)
    agent_js = self._get_agent_js

    if self._is_debug?
      self._logger.info { "agent_js file: #{agent_js}" }
    end

    return unless agent_js

    begin
      page.execute_script(agent_js)
      dom_snapshot_js = <<-JS
      (function() {
        var percyAgentClient = new PercyAgent({ handleAgentCommunication: false });
        return percyAgentClient.snapshot('unused');
      })()
      JS
      return page.evaluate_script(dom_snapshot_js)
    rescue => e
      self._logger.error { "Snapshotting failed. Note that Poltergeist and Rake::Test are no longer supported by percy-capybara. Error: #{e}" }
      return nil
    end
  end

  def self._post_snapshot_to_agent(body)
    http = Net::HTTP.new(AGENT_HOST, AGENT_PORT)
    request = Net::HTTP::Post.new('/percy/snapshot', { 'Content-Type': 'application/json' })
    request.body = body.to_json
    begin
      response = http.request(request)
    rescue => e
      self._logger.error { "Agent rejected snapshot request. Error: #{e}" }
    end
  end

  def self._is_agent_running?
    begin
      Net::HTTP.get(AGENT_HOST, '/percy/healthcheck', AGENT_PORT)
      return true
    rescue => e
      if self._is_debug?
        self._logger.error { "Healthcheck failed, agent is not running: #{e}" }
      end

      return false
    end
  end

  # For Ruby style, require snake_case args but transform them into camelCase for percy-agent.
  def self._keys_to_json(options)
    {
      enable_javascript: :enableJavaScript,
      min_height: :minHeight,
      percy_css: :percyCSS,
    }.each do |ruby_key, json_key|
      if options.has_key? ruby_key
        options[json_key] = options[ruby_key]
        options.delete(ruby_key)
      end
    end
    return options
  end

  def self._is_debug?
    ENV['LOG_LEVEL'] == 'debug'
  end
end
