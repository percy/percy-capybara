require 'percy/capybara/loaders/base_loader'
require 'digest'
require 'find'
require 'pathname'

module Percy
  module Capybara
    module Loaders
      # Resource loader that looks for resources in the specified folder.
      class FilesystemLoader < BaseLoader
        SKIP_RESOURCE_EXTENSIONS = [
          '.map', # Ignore source maps.
          '.gz', # Ignore gzipped files.
        ].freeze
        MAX_FILESIZE_BYTES = 15 * 1024**2 # 15 MB.

        def initialize(options = {})
          # @assets_dir should point to a _compiled_ static assets directory, not source assets.
          @assets_dir = options[:assets_dir]
          @base_url = options[:base_url] || ''

          raise ArgumentError, 'assets_dir is required' if @assets_dir.nil? || @assets_dir == ''
          unless Pathname.new(@assets_dir).absolute?
            raise ArgumentError, "assets_dir needs to be an absolute path. Received: #{@assets_dir}"
          end
          unless Dir.exist?(@assets_dir)
            raise ArgumentError, "assets_dir provided was not found. Received: #{@assets_dir}"
          end

          super
        end

        def snapshot_resources
          [root_html_resource]
        end

        def build_resources
          resources = []
          Find.find(@assets_dir).each do |path|
            # Skip directories.
            next unless FileTest.file?(path)
            # Skip certain extensions.
            next if SKIP_RESOURCE_EXTENSIONS.include?(File.extname(path))
            # Skip large files, these are hopefully downloads and not used in page rendering.
            next if File.size(path) > MAX_FILESIZE_BYTES

            # Replace the assets_dir with the base_url to generate the resource_url
            resource_url = path.sub(@assets_dir, @base_url)

            sha = Digest::SHA256.hexdigest(File.read(path))
            resources << Percy::Client::Resource.new(resource_url, sha: sha, path: path)
          end
          resources
        end
      end
    end
  end
end
