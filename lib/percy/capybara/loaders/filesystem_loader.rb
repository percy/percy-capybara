require 'percy/capybara/loaders/base_loader'
require 'digest'
require 'find'
require 'pathname'

module Percy
  module Capybara
    module Loaders
      # Resource loader that looks for resources in the specified folder.
      class FilesystemLoader < BaseLoader
        def initialize(options = {})
          # @assets_dir should point to a _compiled_ static assets directory, not source assets.
          @assets_dir = options[:assets_dir]
          @base_url = options[:base_url] || '/'

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
          _resources_from_dir(@assets_dir, base_url: @base_url)
        end
      end
    end
  end
end
