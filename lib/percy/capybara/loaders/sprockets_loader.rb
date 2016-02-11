require 'percy/capybara/loaders/base_loader'
require 'digest'
require 'find'
require 'uri'

module Percy
  module Capybara
    module Loaders
      # Resource loader that loads assets via Sprockets (ie. the Rails asset pipeline).
      class SprocketsLoader < BaseLoader
        attr_reader :page
        attr_reader :sprockets_environment
        attr_reader :sprockets_options

        SKIP_RESOURCE_EXTENSIONS = [
          '.js',  # Ignore JavaScript.
          '.map',  # Ignore source maps.
        ]

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
          resources = []

          # Load resources from the asset pipeline.
          _asset_logical_paths.each do |logical_path|
            next if SKIP_RESOURCE_EXTENSIONS.include?(File.extname(logical_path))

            asset = sprockets_environment.find_asset(logical_path)
            content = asset.to_s
            sha = Digest::SHA256.hexdigest(content)

            if defined?(ActionController)
              # Ask Rails where this asset is (this handles asset_hosts, digest paths, etc.).
              resource_url = ActionController::Base.helpers.asset_path(logical_path)
            else
              # TODO: more robust support for Sprockets usage outside Rails, ie Sinatra.
              # How do we find the correct path in that case?
              path = sprockets_options.digest ? asset.digest_path : logical_path
              resource_url = URI.escape("/assets/#{path}")
            end

            next if SKIP_RESOURCE_EXTENSIONS.include?(File.extname(resource_url))
            resources << Percy::Client::Resource.new(resource_url, sha: sha, content: content)
          end

          # Load resources from the public/ directory, if a Rails app.
          if _rails
            public_path = _rails.public_path.to_s
            Find.find(public_path).each do |path|
              # Skip directories.
              next if !FileTest.file?(path)
              # Skip certain extensions.
              next if SKIP_RESOURCE_EXTENSIONS.include?(File.extname(path))

              # Strip the public_path from the beginning of the resource_url.
              # This assumes that everything in the Rails public/ directory is served at the root
              # of the app.
              resource_url = path.sub(public_path, '')

              sha = Digest::SHA256.hexdigest(File.read(path))

              resources << Percy::Client::Resource.new(resource_url, sha: sha, path: path)
            end

          end

          resources
        end

        def _rails
          Rails if defined?(Rails)
        end

        def _asset_logical_paths
          # Re-implement the same technique that "rake assets:precompile" uses to generate the
          # list of asset paths to include in compiled assets. https://goo.gl/sy2R4z
          # We can't just use environment.each_logical_path without any filters, because then
          # we will attempt to compile assets before they're rendered (such as _mixins.css).
          precompile_list = sprockets_options.precompile
          logical_paths = sprockets_environment.each_logical_path(*precompile_list).to_a
          logical_paths += precompile_list.flatten.select do |filename|
            Pathname.new(filename).absolute? if filename.is_a?(String)
          end
          logical_paths.uniq
        end
      end
    end
  end
end
