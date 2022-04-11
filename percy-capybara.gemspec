require_relative './lib/percy/version'

Gem::Specification.new do |spec|
  spec.name          = 'percy-capybara'
  spec.version       = PercyCapybara::VERSION
  spec.authors       = ['Perceptual Inc.']
  spec.email         = ['team@percy.io']
  spec.summary       = %q{Percy visual testing for Capybara}
  spec.description   = %q{}
  spec.homepage      = ''
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.3.0'

  spec.metadata = {
    'bug_tracker_uri' => 'https://github.com/percy/percy-capybara/issues',
    'source_code_uri' => 'https://github.com/percy/percy-capybara',
  }

  spec.files         = Dir.glob("{lib}/**/*") + %w(LICENSE README.md)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'capybara', '>= 3'

  spec.add_development_dependency 'selenium-webdriver', '>= 4.0.0'
  spec.add_development_dependency 'geckodriver-bin', '~> 0.28.0'
  spec.add_development_dependency 'bundler', '>= 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.5'
  spec.add_development_dependency 'capybara', '~> 3.36.0'
  spec.add_development_dependency 'percy-style', '~> 0.7.0'
end
