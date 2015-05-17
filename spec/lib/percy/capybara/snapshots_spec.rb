require 'digest'

RSpec.describe Percy::Capybara::Snapshots do
  # Start a temp webserver that serves the testdata directory.
  around(:all) do |example|
    destination_dir = File.expand_path('../testdata/', __FILE__)
    port = get_random_open_port
    @temp_url = "http://localhost:#{port}"

    # Note: using this form of popen to keep stdout and stderr silent and captured.
    process = IO.popen([
      'ruby', '-run', '-e', 'httpd', destination_dir, '-p', port.to_s, err: [:child, :out]
    ].flatten)
    begin
      example.run
    ensure
      Process.kill('INT', process.pid)
    end
  end
  before(:all) { Capybara.app_host = @temp_url }

  describe '#_find_resources', type: :feature, js: true do
    it 'includes the root DOM HTML' do
      visit '/'
      percy_capybara = Percy::Capybara.new
      resources = percy_capybara.send(:_find_resources, page)

      root_resource = resources.first
      expect(root_resource.is_root).to be_truthy
      expect(root_resource.mimetype).to eq('text/html')
      expect(root_resource.resource_url).to match(/http:\/\/localhost:\d+\//)
      expect(root_resource.content).to include('Hello World!')
      expect(root_resource.sha).to eq(Digest::SHA256.hexdigest(root_resource.content))
    end
  end
end
