module Percy
  def self.client_info
    "percy-capybara/#{VERSION}"
  end

  def self.environment_info
    env_strings = [
      "rails/#{self._rails_version}",
      "sinatra/#{self._sinatra_version}",
      "capybara/#{self.capybara_version}",
      "ember-cli-rails/#{self._ember_cli_rails_version}",
    ].reject do |info|
      info =~ /\/$/ # reject if version is empty
    end
    env_strings.empty? ? 'unknown' : env_strings.join('; ')
  end

  def self.capybara_version
    Capybara::VERSION if defined? Capybara
  end

  def self._ember_cli_rails_version
    return unless defined? EmberCli

    require 'ember_cli/version'
    EmberCli::VERSION
  end

  def self._rails_version
    Rails.version if defined? Rails
  end

  def self._sinatra_version
    Sinatra::VERSION if defined? Sinatra
  end
end
