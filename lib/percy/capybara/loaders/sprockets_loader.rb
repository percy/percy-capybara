require 'percy/capybara/loaders/base_loader'
require 'digest'
require 'find'
require 'set'
require 'addressable/uri'

module Percy
  module Capybara
    module Loaders
      # Resource loader that loads assets via Sprockets (ie. the Rails asset pipeline).
      class SprocketsLoader < BaseLoader
        attr_reader :page
        attr_reader :sprockets_environment
        attr_reader :sprockets_options

        SKIP_RESOURCE_EXTENSIONS = [
          '.map', # Ignore source maps.
          '.gz', # Ignore gzipped files.
        ].freeze
        MAX_FILESIZE_BYTES = 15 * 1024**2 # 15 MB.

        def initialize(options = {})
          @sprockets_environment = options[:sprockets_environment]
          @sprockets_options = options[:sprockets_options]
          super(options)
        end

        def snapshot_resources
          [root_html_resource] + iframes_resources
        end

        def build_resources
          resources = []
          loaded_resource_urls = Set.new

          # Load resources from the asset pipeline.
          _asset_logical_paths.each do |logical_path|
            next if SKIP_RESOURCE_EXTENSIONS.include?(File.extname(logical_path))

            asset = sprockets_environment.find_asset(logical_path)

            # Skip large files, these are hopefully downloads and not used in page rendering.
            next if asset.length > MAX_FILESIZE_BYTES

            content = asset.to_s
            sha = Digest::SHA256.hexdigest(content)

            if defined?(ActionController)
              # Ask Rails where this asset is (this handles asset_hosts, digest paths, etc.).
              resource_url = ActionController::Base.helpers.asset_path(logical_path)
            else
              # TODO: more robust support for Sprockets usage outside Rails, ie Sinatra.
              # How do we find the correct path in that case?
              path = sprockets_options.digest ? asset.digest_path : logical_path
              resource_url = Addressable::URI.escape("/assets/#{path}")
            end

            next if SKIP_RESOURCE_EXTENSIONS.include?(File.extname(resource_url))

            loaded_resource_urls.add(resource_url)
            resources << Percy::Client::Resource.new(resource_url, sha: sha, content: content)
          end

          # Load resources from the public/ directory, if a Rails app.
          if _rails
            public_path = _rails.public_path.to_s
            resources += _resources_from_dir(public_path).reject do |resource|
              # Skip precompiled files already included via the asset pipeline.
              loaded_resource_urls.include?(resource.resource_url)
            end
          end

          resources
        end

        def _rails
          Rails if defined?(Rails)
        end

        def _asset_logical_paths
          if _rails && _rails.application.respond_to?(:precompiled_assets)
            _rails.application.precompiled_assets
          else
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
end
