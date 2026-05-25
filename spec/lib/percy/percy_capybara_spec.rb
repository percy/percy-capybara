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

    # --- Readiness gate ----------------------------------------

    it 'calls evaluate_async_script with waitForReady before serialize' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 200, body: '', headers: {'x-percy-core-version': '1.0.0'})
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/dom.js")
        .to_return(
          status: 200,
          body: 'window.PercyDOM = { serialize: () => ({html: "<html></html>"}), ' \
                'waitForReady: (cfg) => Promise.resolve({ok: true}) };',
          headers: {},
        )
      stub_request(:post, 'http://localhost:5338/percy/snapshot')
        .to_return(status: 200, body: '{"success": "true"}', headers: {})

      visit 'index.html'
      # Opt-in via `readiness: {}` so the SDK runs the gate (matches the
      # opt-in guard added in lib/percy/capybara.rb).
      page.percy_snapshot('readiness-balanced', readiness: {})

      # The snapshot POST body should include readiness_diagnostics from the mock
      expect(WebMock).to have_requested(
        :post, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/snapshot",
      ).with { |req|
        body = JSON.parse(req.body)
        body.dig('dom_snapshot', 'readiness_diagnostics') == {'ok' => true}
      }.once
    end

    it 'skips evaluate_async_script when preset is disabled' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 200, body: '', headers: {'x-percy-core-version': '1.0.0'})
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/dom.js")
        .to_return(
          status: 200,
          body: 'window.PercyDOM = { serialize: () => ({html: "<html></html>"}) };',
          headers: {},
        )
      stub_request(:post, 'http://localhost:5338/percy/snapshot')
        .to_return(status: 200, body: '{"success": "true"}', headers: {})

      # Spy on evaluate_async_script -- it must NOT be called when preset=disabled
      expect(page).to_not receive(:evaluate_async_script)

      visit 'index.html'
      page.percy_snapshot('readiness-disabled', readiness: {preset: 'disabled'})
    end

    it 'still posts the snapshot when evaluate_async_script raises' do
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(status: 200, body: '', headers: {'x-percy-core-version': '1.0.0'})
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/dom.js")
        .to_return(
          status: 200,
          body: 'window.PercyDOM = { serialize: () => ({html: "<html></html>"}) };',
          headers: {},
        )
      stub_request(:post, 'http://localhost:5338/percy/snapshot')
        .to_return(status: 200, body: '{"success": "true"}', headers: {})

      # Force the readiness gate to raise -- the SDK must catch it and still
      # POST the snapshot from the serialize path.
      allow(page).to receive(:evaluate_async_script).and_raise(StandardError, 'boom')

      visit 'index.html'
      page.percy_snapshot('readiness-raise', readiness: {})

      expect(WebMock)
        .to have_requested(:post, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/snapshot")
        .once
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

      # Tolerate the variable number of intermediate driver-bookkeeping
      # requests that percy CLI test mode sometimes records. Find the
      # snapshot POST by URL.
      snap_req = requests.find { |r| r['url'] == '/percy/snapshot' }
      expect(snap_req).not_to be_nil, "expected /percy/snapshot POST, got: #{requests.map { |r| r['url'] }}"
      snap = snap_req['body']
      expect(snap['name']).to eq('Name')
      expect(snap['url']).to eq('http://127.0.0.1:3003/index.html')
      expect(snap['client_info']).to include('percy-capybara')
      expect(snap['environment_info']).to include('capybara')
      expect(snap['widths']).to eq([375])
    end
  end
end
# rubocop:enable RSpec/MultipleDescribes
