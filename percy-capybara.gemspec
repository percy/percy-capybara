# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'percy/capybara/version'

Gem::Specification.new do |spec|
  spec.name          = 'percy-capybara'
  spec.version       = Percy::Capybara::VERSION
  spec.authors       = ['Perceptual Inc.']
  spec.email         = ['team@percy.io']
  spec.summary       = %q{Percy::Capybara}
  spec.description   = %q{}
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'percy-client', '~> 1.4'

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.2'
  spec.add_development_dependency 'capybara', '~> 2.4'
  spec.add_development_dependency 'capybara-webkit', '>= 1.6'
  spec.add_development_dependency 'selenium-webdriver'
  spec.add_development_dependency 'webmock', '~> 1'
  spec.add_development_dependency 'mime-types', '< 3'  # For Ruby 1.9 testing support.
  spec.add_development_dependency 'faraday', '>= 0.8'
  spec.add_development_dependency 'sprockets', '>= 3.2.0'
end
