require 'percy/capybara/loaders/base_loader'
require 'digest'
require 'find'
require 'set'
require 'uri'

module Percy
  module Capybara
    module Loaders
      # Resource loader that loads assets via Sprockets (ie. the Rails asset pipeline).
      class SprocketsLoader < BaseLoader
        attr_reader :page
        attr_reader :sprockets_environment
        attr_reader :sprockets_options

        MAX_FILESIZE_BYTES = 15 * 1024**2  # 15 MB.

        def initialize(options = {})
          @sprockets_environment = options[:sprockets_environment]
          @sprockets_options = options[:sprockets_options]
          @config = options[:config] || {}
          super
        end

        def snapshot_resources
          [root_html_resource] + iframes_resources
        end

        def build_resources
          resources = []
          loaded_resource_urls = Set.new

          # Load resources from the asset pipeline.
          _asset_logical_paths.each do |logical_path|
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

            # Skip ignored paths.
            next if ignored_paths_regex =~ resource_url

            loaded_resource_urls.add(resource_url)
            resources << Percy::Client::Resource.new(resource_url, sha: sha, content: content)
          end

          # Load resources from the public/ directory, if a Rails app.
          if _rails
            public_path = _rails.public_path.to_s
            Find.find(public_path).each do |path|
              # Skip directories.
              next if !FileTest.file?(path)
              # Skip large files, these are hopefully downloads and not used in page rendering.
              next if File.size(path) > MAX_FILESIZE_BYTES

              # Strip the public_path from the beginning of the resource_url.
              # This assumes that everything in the Rails public/ directory is served at the root
              # of the app.
              resource_url = path.sub(public_path, '')

              # Skip ignored paths.
              next if ignored_paths_regex =~ resource_url

              # Skip precompiled files already included via the asset pipeline.
              next if loaded_resource_urls.include?(resource_url)

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

        # Config
        def ignored_paths_regex
          return @ignored_paths_regex if defined?(@ignored_paths_regex)

          sprockets_loader_config = @config['sprockets_loader'] || {}
          ignored_paths = sprockets_loader_config['ignore_paths'] || []
          ignored_paths_compiled = ignored_paths.map { |path| "(?:#{path})" }.join('|')
          unmatchable_regex = /\/\A/
          @ignored_paths_regex = ignored_paths.size > 0 ? Regexp.new(ignored_paths_compiled) : unmatchable_regex
        end
      end
    end
  end
end
