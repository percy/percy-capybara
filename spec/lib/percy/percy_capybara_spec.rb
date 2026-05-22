LABEL = PercyCapybara::PERCY_LABEL

# rubocop:disable RSpec/MultipleDescribes
RSpec.describe PercyCapybara, type: :feature do
  before(:each) do
    WebMock.disable_net_connect!(allow: '127.0.0.1', disallow: 'localhost')
    page.__percy_clear_cache!
  end

  describe 'snapshot', type: :feature do
    it 'disables when healthcheck version is incorrect' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 200, body: '', headers: {'x-percy-core-version': '0.1.0'})

      expect { page.percy_snapshot('Name') }
        .to output("#{LABEL} Unsupported Percy CLI version, 0.1.0\n").to_stdout
    end

    it 'disables when healthcheck version is missing' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 200, body: '', headers: {})

      expect { page.percy_snapshot('Name') }
        .to output(
          "#{LABEL} You may be using @percy/agent which" \
          ' is no longer supported by this SDK. Please uninstall' \
          ' @percy/agent and install @percy/cli instead.' \
          " https://www.browserstack.com/docs/percy/migration/migrate-to-cli\n",
        ).to_stdout
    end

    it 'disables when healthcheck fails' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 500, body: '', headers: {})

      expect { page.percy_snapshot('Name') }
        .to output("#{LABEL} Percy is not running, disabling snapshots\n").to_stdout
    end

    it 'disables when healthcheck fails to connect' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_raise(StandardError)

      expect { page.percy_snapshot('Name') }
        .to output("#{LABEL} Percy is not running, disabling snapshots\n").to_stdout
    end

    it 'throws an error when name is not provided' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 500, body: '', headers: {})

      expect { page.percy_snapshot }.to raise_error(ArgumentError)
    end

    it 'logs an error  when sending a snapshot fails' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 200, body: '', headers: {'x-percy-core-version': '1.0.0'})

      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/dom.js")
        .to_return(
          status: 200,
          body: 'window.PercyDOM = { serialize: () => document.documentElement.outerHTML };',
          headers: {},
        )

      stub_request(:post, 'http://localhost:5338/percy/snapshot')
        .to_return(status: 200, body: '', headers: {})

      expect { page.percy_snapshot('Name') }
        .to output("#{LABEL} Could not take DOM snapshot 'Name'\n").to_stdout
    end

    it 'sends snapshots to the local server' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 200, body: '', headers: {'x-percy-core-version': '1.0.0'})

      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/dom.js")
        .to_return(
          status: 200,
          body: 'window.PercyDOM = { serialize: () => document.documentElement.outerHTML };',
          headers: {},
        )

      stub_request(:post, 'http://localhost:5338/percy/snapshot')
        .to_return(status: 200, body: '{"success": "true" }', headers: {})

      visit 'index.html'
      page.percy_snapshot('Name', widths: [375])

      expect(WebMock)
        .to have_requested(:post, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/snapshot")
        .with(
          body: {
            name: 'Name',
            url: 'http://127.0.0.1:3003/index.html',
            dom_snapshot:
              "<html><head><title>I am a page</title></head><body>Snapshot me\n</body></html>",
            client_info: "percy-capybara/#{PercyCapybara::VERSION}",
            environment_info: "capybara/#{Capybara::VERSION} ruby/#{RUBY_VERSION}",
            widths: [375],
          }.to_json,
        ).once
      expect(page).to have_current_path('/index.html')
    end
  end
end

RSpec.describe PercyCapybara, type: :feature do
  before(:each) do
    WebMock.reset!
    WebMock.allow_net_connect!
    page.__percy_clear_cache!
  end

  describe 'integration', type: :feature do
    it 'sends snapshots to percy server' do
      visit 'index.html'
      page.percy_snapshot('Name', widths: [375])
      sleep 5 # wait for percy server to process
      resp = Net::HTTP.get_response(URI("#{PercyCapybara::PERCY_SERVER_ADDRESS}/test/requests"))
      requests = JSON.parse(resp.body)['requests']
      healthcheck = requests[0]
      expect(healthcheck['url']).to eq('/percy/healthcheck')

      snap = requests[2]['body']
      expect(snap['name']).to eq('Name')
      expect(snap['url']).to eq('http://127.0.0.1:3003/index.html')
      expect(snap['client_info']).to include('percy-capybara')
      expect(snap['environment_info']).to include('capybara')
      expect(snap['widths']).to eq([375])
    end
  end
end

# Unit tests for CORS iframe helper methods
RSpec.describe PercyCapybara do
  # Create a test class that includes the module so we can test private methods
  let(:test_instance) do
    Class.new { include PercyCapybara }.new
  end

  describe '#unsupported_iframe_src?' do
    it 'returns true for nil src' do
      expect(test_instance.send(:unsupported_iframe_src?, nil)).to be true
    end

    it 'returns true for empty src' do
      expect(test_instance.send(:unsupported_iframe_src?, '')).to be true
    end

    it 'returns true for about:blank' do
      expect(test_instance.send(:unsupported_iframe_src?, 'about:blank')).to be true
    end

    it 'returns true for about:srcdoc' do
      expect(test_instance.send(:unsupported_iframe_src?, 'about:srcdoc')).to be true
    end

    it 'returns true for javascript: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'javascript:void(0)')).to be true
    end

    it 'returns true for data: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'data:text/html,<h1>Hi</h1>')).to be true
    end

    it 'returns true for blob: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'blob:https://example.com/abc')).to be true
    end

    it 'returns true for vbscript: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'vbscript:msgbox')).to be true
    end

    it 'returns true for chrome: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'chrome://settings')).to be true
    end

    it 'returns true for chrome-extension: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'chrome-extension://abc/popup.html')).to be true
    end

    it 'returns false for http URLs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'https://example.com')).to be false
    end

    it 'returns false for relative URLs' do
      expect(test_instance.send(:unsupported_iframe_src?, '/iframe.html')).to be false
    end
  end

  describe '#get_origin' do
    it 'extracts origin from http URL' do
      expect(test_instance.send(:get_origin, 'http://example.com/path')).to eq('http://example.com')
    end

    it 'extracts origin from https URL' do
      expect(test_instance.send(:get_origin, 'https://example.com/path')).to eq('https://example.com')
    end

    it 'includes non-default port' do
      expect(test_instance.send(:get_origin, 'http://example.com:8080/path')).to eq('http://example.com:8080')
    end

    it 'excludes default http port 80' do
      expect(test_instance.send(:get_origin, 'http://example.com:80/path')).to eq('http://example.com')
    end

    it 'excludes default https port 443' do
      expect(test_instance.send(:get_origin, 'https://example.com:443/path')).to eq('https://example.com')
    end

    it 'raises for URLs without a host' do
      expect { test_instance.send(:get_origin, 'not-a-url') }.to raise_error(URI::InvalidURIError)
    end
  end

  describe '#process_frame' do
    let(:mock_driver) { double('driver') }
    let(:mock_frame) { double('frame_element') }
    let(:percy_dom_script) { 'window.PercyDOM = { serialize: function() { return {}; } };' }

    before(:each) do
      allow(mock_frame).to receive(:attribute).with('src').and_return('https://other.com/embed')
    end

    it 'returns nil when percyElementId is missing' do
      allow(mock_driver).to receive(:switch_to).and_return(double(
                                                             frame: nil,
                                                             default_content: nil,
                                                           ))
      allow(mock_driver).to receive(:execute_script).and_return(nil, {'html' => '<html></html>'})
      allow(mock_frame).to receive(:attribute).with('data-percy-element-id').and_return(nil)

      result = test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)
      expect(result).to be_nil
    end

    it 'returns correct payload when frame is processed successfully' do
      switch_to_mock = double('switch_to')
      allow(switch_to_mock).to receive(:frame)
      allow(switch_to_mock).to receive(:default_content)
      allow(mock_driver).to receive(:switch_to).and_return(switch_to_mock)
      allow(mock_driver).to receive(:execute_script).and_return(
        nil,
        {'html' => '<html>iframe</html>', 'resources' => [], 'warnings' => []},
      )
      allow(mock_frame).to receive(:attribute).with('data-percy-element-id').and_return('percy-id-1')

      result = test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)

      expect(result).to eq({
                             'iframeData' => {'percyElementId' => 'percy-id-1'},
                             'iframeSnapshot' => {'html' => '<html>iframe</html>', 'resources' => [], 'warnings' => []},
                             'frameUrl' => 'https://other.com/embed',
                           })
    end

    it 'returns nil when switching to frame fails' do
      switch_to_mock = double('switch_to')
      allow(switch_to_mock).to receive(:frame).and_raise(StandardError.new('frame not found'))
      allow(switch_to_mock).to receive(:default_content)
      allow(mock_driver).to receive(:switch_to).and_return(switch_to_mock)

      result = test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)
      expect(result).to be_nil
    end

    it 'returns nil when script execution fails inside frame' do
      switch_to_mock = double('switch_to')
      allow(switch_to_mock).to receive(:frame)
      allow(switch_to_mock).to receive(:default_content)
      allow(mock_driver).to receive(:switch_to).and_return(switch_to_mock)
      allow(mock_driver).to receive(:execute_script).and_raise(StandardError.new('script error'))

      result = test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)
      expect(result).to be_nil
    end

    it 'always restores driver to default content' do
      switch_to_mock = double('switch_to')
      allow(switch_to_mock).to receive(:frame)
      expect(switch_to_mock).to receive(:default_content).at_least(:once)
      allow(mock_driver).to receive(:switch_to).and_return(switch_to_mock)
      allow(mock_driver).to receive(:execute_script).and_raise(StandardError.new('error'))

      test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)
    end
  end
end
# rubocop:enable RSpec/MultipleDescribes
