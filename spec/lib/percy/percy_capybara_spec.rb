LABEL = PercyCapybara::PERCY_LABEL

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

    # --- .percy.yml config <-> per-snapshot merge precedence ----

    it 'merges .percy.yml config with per-call options (per-call wins, no dup keys)' do
      # Healthcheck returns a config with a snapshot block: a config-only key
      # (enableJavaScript) plus a percyCSS the per-call option will override.
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(
          status: 200,
          body: {
            config: {
              'snapshot' => {
                'enableJavaScript' => true,
                'percyCSS' => 'FROM_CONFIG',
              },
            },
          }.to_json,
          headers: {'x-percy-core-version': '1.0.0'},
        )
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/dom.js")
        .to_return(
          status: 200,
          body: 'window.PercyDOM = { serialize: () => ({html: "<html></html>"}) };',
          headers: {},
        )
      stub_request(:post, 'http://localhost:5338/percy/snapshot')
        .to_return(status: 200, body: '{"success": "true"}', headers: {})

      # Capture the JS string passed to PercyDOM.serialize without a real browser.
      # evaluate_script is called twice: once to inject @percy/dom (fetch_percy_dom),
      # then once for the serialize call we want to inspect.
      serialize_script = nil
      allow(page).to receive(:evaluate_script) do |script|
        serialize_script = script if script.include?('PercyDOM.serialize')
        {'html' => '<html></html>'}
      end

      page.percy_snapshot('merge-precedence', percyCSS: 'FROM_CALL')

      expect(serialize_script).to_not be_nil
      # Extract the JSON object handed to PercyDOM.serialize.
      # Non-greedy so we stop at the matching close brace and don't swallow the
      # trailing `) })()` from the wrapping IIFE.
      json = serialize_script[/PercyDOM\.serialize\((\{.*?\})\)/m, 1]
      merged = JSON.parse(json)

      # Config-only key survives the merge.
      expect(merged['enableJavaScript']).to eq(true)
      # Per-call option overrides the config value.
      expect(merged['percyCSS']).to eq('FROM_CALL')
      # No duplicate percyCSS key (string vs symbol collision avoided).
      expect(json.scan(/"percyCSS"/).size).to eq(1)
    end

    it 'deep-merges nested config blocks with per-call options (per-call wins at leaves)' do
      # Config has a nested discovery block; the per-call discovery overrides
      # only one leaf. A shallow merge would drop networkIdleTimeout entirely;
      # the deep merge must keep it while applying the per-call disableCache.
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/healthcheck")
        .to_return(
          status: 200,
          body: {
            config: {
              'snapshot' => {
                'discovery' => {
                  'networkIdleTimeout' => 50,
                  'disableCache' => false,
                },
              },
            },
          }.to_json,
          headers: {'x-percy-core-version': '1.0.0'},
        )
      stub_request(:get, "#{PercyCapybara::PERCY_SERVER_ADDRESS}/percy/dom.js")
        .to_return(
          status: 200,
          body: 'window.PercyDOM = { serialize: () => ({html: "<html></html>"}) };',
          headers: {},
        )
      stub_request(:post, 'http://localhost:5338/percy/snapshot')
        .to_return(status: 200, body: '{"success": "true"}', headers: {})

      serialize_script = nil
      allow(page).to receive(:evaluate_script) do |script|
        serialize_script = script if script.include?('PercyDOM.serialize')
        {'html' => '<html></html>'}
      end

      page.percy_snapshot('deep-merge', discovery: {disableCache: true})

      expect(serialize_script).to_not be_nil
      json = serialize_script[/PercyDOM\.serialize\((\{.*?\})\)/m, 1]
      merged = JSON.parse(json)

      # Nested config-only leaf survives the deep merge.
      expect(merged.dig('discovery', 'networkIdleTimeout')).to eq(50)
      # Per-call leaf overrides the nested config value.
      expect(merged.dig('discovery', 'disableCache')).to eq(true)
    end
  end
end
