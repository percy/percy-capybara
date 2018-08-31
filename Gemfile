source 'https://rubygems.org'

# Specify your gem's dependencies in percy-capybara.gemspec
gemspec

gem 'guard-rspec', require: false

# (for development)
# gem 'percy-client', path: '~/src/percy-client'
gem 'percy-client', :git => 'https://github.com/percy/percy-client.git', :branch => 'map/update-to-token-only-build-endpoint'

group :test, :development do
  gem 'pry'
end
