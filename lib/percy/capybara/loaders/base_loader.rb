require 'pathname'
require 'percy/capybara'

module Percy
  module Capybara
    module Loaders
      class BaseLoader
        # Modified version of Diego Perini's URL regex. https://gist.github.com/dperini/729294
        URL_REGEX = Regexp.new(
          # protocol identifier
          '((?:https?:)?//)' \
          '(' +
            # IP address exclusion
            # private & local networks
            '(?!(?:10|127)(?:\\.\\d{1,3}){3})' \
            '(?!(?:169\\.254|192\\.168)(?:\\.\\d{1,3}){2})' \
            '(?!172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.\\d{1,3}){2})' +
            # IP address dotted notation octets
            # excludes loopback network 0.0.0.0
            # excludes reserved space >= 224.0.0.0
            # excludes network & broacast addresses
            # (first & last IP address of each class)
            '(?:[1-9]\\d?|1\\d\\d|2[01]\\d|22[0-3])' \
            '(?:\\.(?:1?\\d{1,2}|2[0-4]\\d|25[0-5])){2}' \
            '(?:\\.(?:[1-9]\\d?|1\\d\\d|2[0-4]\\d|25[0-4]))' \
          '|' +
            # host name
            '(?:(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)' +
            # domain name
            '(?:\\.(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)*' \
          ')' +
          # port number
          '(:\\d{2,5})?' +
          # resource path
          "(/[^\\s\"']*)?",
        )

        SKIP_RESOURCE_EXTENSIONS = [
          '.map', # Ignore source maps.
          '.gz', # Ignore gzipped files.
        ].freeze

        MAX_FILESIZE_BYTES = 15 * 1024**2 # 15 MB.

        attr_reader :page

        # @param [Capybara::Session] page The Capybara page.
        # @param [bool] include_iframes Include iframes in the snapshot
        def initialize(options = {})
          @page = options[:page]
          @include_iframes = options[:include_iframes] || false
        end

        def build_resources
          raise NotImplementedError, 'subclass must implement abstract method'
        end

        def snapshot_resources
          raise NotImplementedError, 'subclass must implement abstract method'
        end

        # @private
        def root_html_resource
          Percy::Client::Resource.new(
            current_path, is_root: true, mimetype: 'text/html', content: page.html,
          )
        end

        # Transformed version of the current URL to be a relative path.
        # This important because Rack::Test uses "www.example.com" as the actual current URL,
        # which would force Percy to actually render example.com instead of the page. By always
        # using a URL path as the resource URL, we guarantee that Percy will render what it's given.
        #
        # @private
        def current_path
          current_url = page.current_url
          url_match = URL_REGEX.match(current_url)
          return url_match[4] if url_match

          # Special case: prepend a slash to the path to force a valid URL for things like
          # "about:srcdoc" iframe srcdoc pages.
          current_url = "/#{current_url}" if current_url[0] != '/'

          current_url
        end

        # NOTES:
        # - Doesn't handle multiple iframes with the same URL (`src` attribute)
        # @private
        def iframes_resources
          return [] unless @include_iframes

          resources = []

          page.all(:css, 'iframe').each do |iframe_element|
            iframe_url = iframe_element[:src]
            root_page_host = page.current_host
            begin
              page.within_frame(iframe_element) do
                next unless page.current_host == root_page_host
                path = URI.parse(iframe_url).path
                content = page.html
                sha = Digest::SHA256.hexdigest(content)
                resources <<
                  Percy::Client::Resource.new(
                    path,
                    content: content,
                    sha: sha,
                    mimetype: 'text/html',
                  )
              end
            rescue StandardError => e
              # Skip frame not found errors. This library doesn't explicitly depend on Poltergeist,
              # so we check the string class name.
              raise e unless e.class.to_s == 'Capybara::Poltergeist::FrameNotFound' ||
                  e.class.to_s == 'Capybara::Poltergeist::TimeoutError'
            end
          end

          resources
        rescue ::Capybara::NotSupportedByDriverError
          []
        end

        def _resources_from_dir(root_dir, base_url: '/')
          resources = []

          _find_files(root_dir).each do |path|
            # Skip certain extensions.
            next if SKIP_RESOURCE_EXTENSIONS.include?(File.extname(path))
            # Skip large files, these are hopefully downloads and not used in page rendering.
            next if File.size(path) > MAX_FILESIZE_BYTES

            # Replace the assets_dir with the base_url to generate the resource_url
            resource_url = _uri_join(base_url, path.sub(root_dir.to_s, ''))

            sha = Digest::SHA256.hexdigest(File.read(path))

            resources << Percy::Client::Resource.new(resource_url, sha: sha, path: path)
          end

          resources
        end

        # A simplified version of Find.find that only returns files and follows symlinks.
        def _find_files(*paths)
          paths.flatten.map do |path|
            path = Pathname.new(path)
            path.file? ? [path.to_s] : _find_files(path.children)
          end.flatten
        end

        def _uri_join(*paths)
          # We must swap File::SEPARATOR for '/' here because on Windows File.join
          # will use backslashes and this is a URL.
          File.join(paths).gsub(File::SEPARATOR, '/')
        end
      end
    end
  end
end
