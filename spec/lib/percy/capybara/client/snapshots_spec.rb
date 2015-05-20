require 'json'
require 'digest'

RSpec.describe Percy::Capybara::Client::Snapshots do
  let(:capybara_client) { Percy::Capybara::Client.new }

  # Start a temp webserver that serves the testdata directory.
  # You can test this server manually by running:
  # ruby -run -e httpd spec/lib/percy/capybara/testdata -p 9090
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
    verify_server_up(Capybara.app_host)
  end
  after(:all) { Process.kill('INT', @process.pid) }

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
      # For capybara-webkit.
      page.driver.respond_to?(:allow_url) && page.driver.allow_url('maxcdn.bootstrapcdn.com')

      visit '/test-css.html'
      resources = capybara_client.send(:_get_css_resources, page)

      expect(resources.length).to eq(7)
      expect(resources.collect(&:mimetype).uniq).to eq(['text/css'])

      resource = resources.select do |resource|
        resource.resource_url.match(/http:\/\/localhost:\d+\/css\/base\.css/)
      end.fetch(0)
      expect(resource.is_root).to be_falsey

      expect(resource.content).to include('.colored-by-base { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = resources.select do |resource|
        resource.resource_url.match(/http:\/\/localhost:\d+\/css\/simple-imports\.css/)
      end.fetch(0)
      expect(resource.is_root).to be_falsey
      expect(resource.content).to include('@import url("imports.css")')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = resources.select do |resource|
        resource.resource_url.match(/http:\/\/localhost:\d+\/css\/imports\.css/)
      end.fetch(0)
      expect(resource.is_root).to be_falsey
      expect(resource.content).to include('.colored-by-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = resources.select do |resource|
        resource.resource_url.match(/http:\/\/localhost:\d+\/css\/level0-imports\.css/)
      end.fetch(0)
      expect(resource.is_root).to be_falsey
      expect(resource.content).to include('@import url("level1-imports.css")')
      expect(resource.content).to include('.colored-by-level0-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = resources.select do |resource|
        resource.resource_url.match(/http:\/\/localhost:\d+\/css\/level1-imports\.css/)
      end.fetch(0)
      expect(resource.is_root).to be_falsey
      expect(resource.content).to include('@import url("level2-imports.css")')
      expect(resource.content).to include('.colored-by-level1-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = resources.select do |resource|
        resource.resource_url.match(/http:\/\/localhost:\d+\/css\/level2-imports\.css/)
      end.fetch(0)
      expect(resource.is_root).to be_falsey
      expect(resource.content).to include(".colored-by-level2-imports { color: red; }")
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = resources.select do |resource|
        resource.resource_url == (
          'https://maxcdn.bootstrapcdn.com/bootstrap/3.3.4/css/bootstrap.min.css')
      end.fetch(0)
      expect(resource.is_root).to be_falsey
      expect(resource.content).to include('Bootstrap v3.3.4 (http://getbootstrap.com)')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))
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
            'links' => {
              'self' => "/api/v1/snapshots/123",
              'missing-resources' => {
                'linkage' => [
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

        resource_map = capybara_client.snapshot(page)
      end
    end
  end
end
