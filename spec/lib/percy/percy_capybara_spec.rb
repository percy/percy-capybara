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
# rubocop:enable RSpec/MultipleDescribes
