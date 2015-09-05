require 'tempfile'
require 'shellwords'

module Percy
  module Capybara
    module HttpFetcher
      class Response < Struct.new(:body, :content_type); end

      def self.fetch(url)
        tempfile = Tempfile.new('percy-capybara-fetch')
        temppath = tempfile.path

        # Close and delete the tempfile, we just wanted the name. Also, we use the existence of the
        # file as a signal below.
        tempfile.close
        tempfile.unlink

        # Use curl as a magical subprocess weapon which escapes this Ruby sandbox and is not
        # influenced by any HTTP middleware/restrictions. This helps us avoid causing lots of
        # problems for people using gems like VCR/WebMock. We also disable certificate checking
        # because, as odd as that is, it's the default state for Selenium Firefox and others.
        output = `curl --insecure -v -o #{temppath} "#{url.shellescape}" 2>&1`
        content_type = output.match(/< Content-Type:(.*)/i)
        content_type = content_type[1].strip if content_type

        if File.exist?(temppath)
          response = Percy::Capybara::HttpFetcher::Response.new(File.read(temppath), content_type)
          # We've broken the tempfile so it won't get deleted when garbage collected. Delete!
          File.delete(temppath)
          return if response.body == ''
          response
        end
      end
    end
  end
end
