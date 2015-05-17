require 'json'
require 'digest'

RSpec.describe Percy::Capybara::Snapshots do
  # Start a temp webserver that serves the testdata directory.
  around(:each) do |example|
    destination_dir = File.expand_path('../testdata/', __FILE__)
    port = get_random_open_port

    Capybara.app_host = "http://localhost:#{port}"
    Capybara.run_server = false

    # Note: using this form of popen to keep stdout and stderr silent and captured.
    process = IO.popen([
      'ruby', '-run', '-e', 'httpd', destination_dir, '-p', port.to_s, err: [:child, :out]
    ].flatten)

    # Block until the server is up.
    verify_server_up(Capybara.app_host)

    begin
      example.run
    ensure
      Process.kill('INT', process.pid)
    end
  end

  describe '#_find_resources', type: :feature, js: true do
    it 'includes the root DOM HTML' do
      visit '/'
      percy_capybara = Percy::Capybara.new
      resource_map = percy_capybara.send(:_find_resources, page)

      root_resource = resource_map.values.first
      expect(root_resource.is_root).to be_truthy
      expect(root_resource.mimetype).to eq('text/html')
      expect(root_resource.resource_url).to match(/http:\/\/localhost:\d+\//)
      expect(root_resource.content).to include('Hello World!')
      expect(root_resource.sha).to eq(Digest::SHA256.hexdigest(root_resource.content))
    end
  end
  describe '#snapshot', type: :feature, js: true do
    context 'simple page with no resources' do
      let(:content) { '<html><body>Hello World!</body><head></head></html>' }

      it 'creates a snapshot and uploads missing resource' do
        visit '/'
        percy_capybara = Percy::Capybara.new

        mock_response = {
          'data' => {
            'id' => '123',
            'type' => 'builds',
          },
        }
        stub_request(:post, 'https://percy.io/api/v1/repos/percy/percy-capybara/builds/')
          .to_return(status: 201, body: mock_response.to_json)

        resource_map = percy_capybara.send(:_find_resources, page)
        sha = resource_map.keys.first
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
                    'id' => sha,
                  },
                ],
              },
            },
          },
        }
        stub_request(:post, 'https://percy.io/api/v1/builds/123/snapshots/')
          .to_return(status: 201, body: mock_response.to_json)

        stub_request(:post, "https://percy.io/api/v1/builds/123/resources/")
          .with(body: /#{sha}/).to_return(status: 201, body: {success: true}.to_json)

        resource_map = percy_capybara.snapshot(page)
      end
    end
  end
end
