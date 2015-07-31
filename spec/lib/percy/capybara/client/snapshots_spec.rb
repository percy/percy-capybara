require 'json'
require 'digest'

RSpec.describe Percy::Capybara::Client::Snapshots, type: :feature do
  let(:capybara_client) { Percy::Capybara::Client.new(enabled: true) }

  # Start a temp webserver that serves the testdata directory.
  # You can test this server manually by running:
  # ruby -run -e httpd spec/lib/percy/capybara/client/testdata/ -p 9090
  before(:all) do
    port = get_random_open_port
    Capybara.app_host = "http://localhost:#{port}"
    Capybara.run_server = false

    # Note: using this form of popen to keep stdout and stderr silent and captured.
    dir = File.expand_path('../testdata/', __FILE__)
    @process = IO.popen([
      'ruby', '-run', '-e', 'httpd', dir, '-p', port.to_s, err: [:child, :out]
    ].flatten)

    # Block until the server is up.
    WebMock.disable_net_connect!(allow_localhost: true)
    verify_server_up(Capybara.app_host)
  end
  after(:all) { Process.kill('INT', @process.pid) }

  before(:each, js: true) do
    # Special setting for capybara-webkit. If clients are using capybara-webkit they would
    # also have to have this setting enabled since apparently all resources are blocked by default.
    page.driver.respond_to?(:allow_url) && page.driver.allow_url('*')
  end

  def find_resource(resources, regex)
    begin
      resources.select { |resource| resource.resource_url.match(regex) }.fetch(0)
    rescue IndexError
      raise "Missing expected image with resource_url that matches: #{regex}"
    end
  end

  describe '#_should_include_url?' do
    it 'returns true for valid, local URLs' do
      expect(capybara_client._should_include_url?('http://localhost/')).to eq(true)
      expect(capybara_client._should_include_url?('http://localhost:123/')).to eq(true)
      expect(capybara_client._should_include_url?('http://localhost/foo')).to eq(true)
      expect(capybara_client._should_include_url?('http://localhost:123/foo')).to eq(true)
      expect(capybara_client._should_include_url?('http://localhost/foo/test.html')).to eq(true)
      expect(capybara_client._should_include_url?('http://127.0.0.1/')).to eq(true)
      expect(capybara_client._should_include_url?('http://127.0.0.1:123/')).to eq(true)
      expect(capybara_client._should_include_url?('http://127.0.0.1/foo')).to eq(true)
      expect(capybara_client._should_include_url?('http://127.0.0.1:123/foo')).to eq(true)
      expect(capybara_client._should_include_url?('http://127.0.0.1/foo/test.html')).to eq(true)
      expect(capybara_client._should_include_url?('http://0.0.0.0/foo/test.html')).to eq(true)
      # Also works for paths:
      expect(capybara_client._should_include_url?('/')).to eq(true)
      expect(capybara_client._should_include_url?('/foo')).to eq(true)
      expect(capybara_client._should_include_url?('/foo/test.png')).to eq(true)
    end
    it 'returns false for invalid URLs' do
      expect(capybara_client._should_include_url?('')).to eq(false)
      expect(capybara_client._should_include_url?('http://local host/foo')).to eq(false)
      expect(capybara_client._should_include_url?('bad-url/')).to eq(false)
      expect(capybara_client._should_include_url?('bad-url/foo/test.html')).to eq(false)
    end
    it 'returns false for data URLs' do
      expect(capybara_client._should_include_url?('data:image/gif;base64,R0')).to eq(false)
    end
    it 'returns false for remote URLs' do
      expect(capybara_client._should_include_url?('http://foo/')).to eq(false)
      expect(capybara_client._should_include_url?('http://example.com/')).to eq(false)
      expect(capybara_client._should_include_url?('http://example.com/foo')).to eq(false)
      expect(capybara_client._should_include_url?('https://example.com/foo')).to eq(false)
    end
  end
  describe '#_get_root_html_resource', type: :feature, js: true do
    it 'includes the root DOM HTML' do
      visit '/'
      resource = capybara_client.send(:_get_root_html_resource, page)

      expect(resource.is_root).to be_truthy
      expect(resource.mimetype).to eq('text/html')
      expect(resource.resource_url).to match(/http:\/\/localhost:\d+\//)
      expect(resource.content).to include('Hello World!')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))
    end
  end
  describe '#_get_css_resources', type: :feature, js: true do
    it 'includes all linked and imported stylesheets' do
      visit '/test-css.html'
      resources = capybara_client.send(:_get_css_resources, page)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/base\.css/)

      expect(resource.content).to include('.colored-by-base { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/simple-imports\.css/)
      expect(resource.content).to include("@import url('imports.css');")
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/imports\.css/)
      expect(resource.content).to include('.colored-by-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/level0-imports\.css/)
      expect(resource.content).to include("@import url('level1-imports.css')")
      expect(resource.content).to include('.colored-by-level0-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/level1-imports\.css/)
      expect(resource.content).to include("@import url('level2-imports.css')")
      expect(resource.content).to include('.colored-by-level1-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, /http:\/\/localhost:\d+\/css\/level2-imports\.css/)
      expect(resource.content).to include(".colored-by-level2-imports { color: red; }")
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      expect(resources.length).to eq(6)
      expect(resources.collect(&:mimetype).uniq).to eq(['text/css'])
      expect(resources.collect(&:is_root).uniq).to match_array([nil])
    end
  end
  describe '#_get_image_resources', type: :feature, js: true do
    it 'includes all images' do
      visit '/test-images.html'
      resources = capybara_client.send(:_get_image_resources, page)

      # The order of these is just for convenience, they match the order in test-images.html.

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/img-relative\.png/)
      content = File.read(File.expand_path('../testdata/images/img-relative.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/img-relative-to-root\.png/)
      content = File.read(File.expand_path('../testdata/images/img-relative-to-root.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/percy\.svg/)
      content = File.read(File.expand_path('../testdata/images/percy.svg', __FILE__))
      # In Ruby 1.9.3 the SVG mimetype is not registered so our mini ruby webserver doesn't serve
      # the correct content type. Allow either to work here so we can test older Rubies fully.
      expect(resource.mimetype).to match(/image\/svg\+xml|application\/octet-stream/)
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/bg-relative\.png/)
      content = File.read(File.expand_path('../testdata/images/bg-relative.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/bg-relative-to-root\.png/)
      content = File.read(File.expand_path('../testdata/images/bg-relative-to-root.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/bg-stacked\.png/)
      content = File.read(File.expand_path('../testdata/images/bg-stacked.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/srcset-base\.png/)
      content = File.read(File.expand_path('../testdata/images/srcset-base.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/srcset-first\.png/)
      content = File.read(File.expand_path('../testdata/images/srcset-first.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, /http:\/\/localhost:\d+\/images\/srcset-second\.png/)
      content = File.read(File.expand_path('../testdata/images/srcset-second.png', __FILE__))
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource_urls = resources.collect(&:resource_url).map do |url|
        url.gsub(/localhost:\d+/, 'localhost')
      end
      expect(resource_urls).to match_array([
        "http://localhost/images/img-relative.png",
        "http://localhost/images/img-relative-to-root.png",
        "http://localhost/images/percy.svg",
        "http://localhost/images/srcset-base.png",
        "http://localhost/images/srcset-first.png",
        "http://localhost/images/srcset-second.png",
        "http://localhost/images/bg-relative.png",
        "http://localhost/images/bg-relative-to-root.png",
        "http://localhost/images/bg-stacked.png"
      ])
      expect(resources.collect(&:is_root).uniq).to match_array([nil])
    end
  end
  describe '#snapshot', type: :feature, js: true do
    context 'simple page with no resources' do
      let(:content) { '<html><body>Hello World!</body><head></head></html>' }

      it 'creates a snapshot and uploads missing resource' do
        visit '/'

        mock_response = {
          'data' => {
            'id' => '123',
            'type' => 'builds',
          },
        }
        stub_request(:post, 'https://percy.io/api/v1/repos/percy/percy-capybara/builds/')
          .to_return(status: 201, body: mock_response.to_json)

        resource = capybara_client.send(:_get_root_html_resource, page)
        mock_response = {
          'data' => {
            'id' => '256',
            'type' => 'snapshots',
            'relationships' => {
              'self' => "/api/v1/snapshots/123",
              'missing-resources' => {
                'data' => [
                  {
                    'type' => 'resources',
                    'id' => resource.sha,
                  },
                ],
              },
            },
          },
        }
        stub_request(:post, 'https://percy.io/api/v1/builds/123/snapshots/')
          .to_return(status: 201, body: mock_response.to_json)

        stub_request(:post, "https://percy.io/api/v1/builds/123/resources/")
          .with(body: /#{resource.sha}/).to_return(status: 201, body: {success: true}.to_json)

        expect(capybara_client).to receive(:_get_root_html_resource)
          .with(page).once.and_call_original
        expect(capybara_client).to receive(:_get_css_resources)
          .with(page).once.and_call_original
        expect(capybara_client).to receive(:_get_image_resources)
          .with(page).once.and_call_original

        stub_request(:post, "https://percy.io/api/v1/snapshots/256/finalize")
          .to_return(status: 200, body: '{"success":true}')

        expect(capybara_client.snapshot(page)).to eq(true)
      end
    end
  end
end
