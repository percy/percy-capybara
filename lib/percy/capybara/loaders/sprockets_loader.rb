require 'percy/capybara/loaders/base_loader'
require 'digest'
require 'uri'

module Percy
  module Capybara
    module Loaders
      # Resource loader that loads assets via Sprockets (ie. the Rails asset pipeline).
      class SprocketsLoader < BaseLoader
        attr_reader :page
        attr_reader :sprockets_environment
        attr_reader :sprockets_options

        def initialize(options = {})
          @sprockets_environment = options[:sprockets_environment]
          @sprockets_options = options[:sprockets_options]
          super
        end

        def snapshot_resources
          # When loading via Sprockets, all other resources are associated to the build, so the only
          # snapshot resource to upload is the root HTML.
          [root_html_resource]
        end

        def build_resources
          # Re-implement the same technique that "rake assets:precompile" uses to generate the
          # list of asset paths to include in compiled assets. https://goo.gl/sy2R4z
          # We can't just use environment.each_logical_path without any filters, because then
          # we will attempt to compile assets before they're rendered (such as _mixins.css).
          precompile_list = sprockets_options.precompile
          logical_paths = sprockets_environment.each_logical_path(*precompile_list).to_a
          logical_paths += precompile_list.flatten.select do |filename|
            Pathname.new(filename).absolute? if filename.is_a?(String)
          end

          resources = []
          logical_paths.each do |logical_path|
            content = sprockets_environment.find_asset(logical_path).to_s
            sha = Digest::SHA256.hexdigest(content)
            resource_url = URI.escape("/assets/#{logical_path}")
            resources << Percy::Client::Resource.new(
              resource_url, sha: sha, content: content)
          end
          resources
        end
      end
    end
  end
end
