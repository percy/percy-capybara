require 'bundler/gem_tasks'

AGENT_BIN = File.join(File.dirname(__FILE__), './node_modules/.bin/percy')

desc 'Run all tests and upload snapshots'
task :snapshots do
  unless File.exist?(AGENT_BIN)
    abort "Could not find #{AGENT_BIN}. Please run npm install and try again."
  end
  sh %( #{AGENT_BIN} exec -- bundle exec rspec  )
end
