require 'logger'
require 'net/http'
require 'uri'
require 'json'
require 'percy/capybara/environment'

module Percy
  AGENT_HOST = "localhost"
  # Technically, the port is configurable when you run the agent. One day we might want
  # to make the port configurable in this SDK as well.
  AGENT_PORT = 5338
  AGENT_JS_PATH= File.join(File.dirname(__FILE__), "../../vendor/percy-agent.js")

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
      clientInfo: Percy::Capybara.client_info,
      environmentInfo: Percy::Capybara.environment_info,
    }
    body = body.merge(self._keys_to_json(options))
    self._post_snapshot_to_agent(body)
  end

  private
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
      return File.read(AGENT_JS_PATH)
    rescue => e
      self._logger.error { "Could not read percy-agent.js. Snapshots won't work. Error: #{e}" }
      return nil
    end
  end

  def self._make_dom_snapshot(page)
    agent_js = self._get_agent_js
    return unless agent_js

    page.execute_script(agent_js)
    dom_snapshot_js = <<-JS
    (function() {
      var percyAgentClient = new PercyAgent({ handleAgentCommunication: false });
      return percyAgentClient.snapshot('unused');
    })()
    JS
    page.evaluate_script(dom_snapshot_js)
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
    rescue
      return false
    end
  end

  # For backwards-compatibility, transform select option keys from snake_case to camelCase.
  def self._keys_to_json(options)
    {
      enable_javascript: :enableJavascript,
      minimum_height: :minHeight,
    }.each do |ruby_key, json_key|
      if options.has_key? ruby_key
        options[json_key] = options[ruby_key]
        options.delete(ruby_key)
      end
    end
    return options
  end
end
