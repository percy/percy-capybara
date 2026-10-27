# Unit tests for closed shadow root exposure
RSpec.describe PercyCapybara do
  let(:test_instance) { Class.new { include PercyCapybara }.new }
  let(:driver) { double('driver') }

  def call(method, *args)
    test_instance.send(method, *args)
  end

  describe '#get_serialized_dom' do
    it 'exposes closed shadow roots before serializing on a Selenium driver' do
      allow(driver).to receive(:find_elements).and_return([])
      allow(driver).to receive(:switch_to)
      page = double('page', current_url: 'https://example.com/',
                            driver: double('cap_driver', browser: driver),)
      expect(test_instance).to receive(:expose_closed_shadow_roots).with(driver, {}).ordered
      expect(page).to receive(:evaluate_script).ordered.and_return('html' => '<page/>')
      call(:get_serialized_dom, page, {}, 'script')
    end

    it 'does not try on non-Selenium drivers (rack_test, Cuprite)' do
      page = double('page', current_url: 'https://example.com/',
                            driver: double('rack_test_driver'),
                            evaluate_script: {'html' => '<page/>'},)
      expect(test_instance).to_not receive(:expose_closed_shadow_roots)
      expect(call(:get_serialized_dom, page, {}, 'script')).to eq('html' => '<page/>')
    end
  end

  describe '#expose_closed_shadow_roots' do
    before(:each) do
      allow(driver).to receive(:respond_to?).and_return(false)
      allow(driver).to receive(:capabilities).and_return(double('caps', browser_name: 'firefox'))
    end

    it 'does nothing when disableShadowDOM is set' do
      expect(test_instance).to_not receive(:closed_shadow_classic_allowed?)
      call(:expose_closed_shadow_roots, driver, 'disableShadowDOM' => true)
      call(:expose_closed_shadow_roots, driver, disableShadowDOM: true)
    end

    it 'stops after CDP succeeds' do
      edge_caps = double('caps', browser_name: 'MicrosoftEdge')
      allow(driver).to receive(:capabilities).and_return(edge_caps)
      allow(driver).to receive(:respond_to?).with(:execute_cdp).and_return(true)
      expect(test_instance).to receive(:expose_closed_shadow_roots_cdp).and_return(true)
      expect(test_instance).to_not receive(:closed_shadow_classic_allowed?)
      call(:expose_closed_shadow_roots, driver, {})
    end

    it 'never uses CDP on firefox' do
      allow(driver).to receive(:respond_to?).with(:execute_cdp).and_return(true)
      expect(test_instance).to_not receive(:expose_closed_shadow_roots_cdp)
      allow(test_instance).to receive(:closed_shadow_classic_allowed?).and_return(false)
      call(:expose_closed_shadow_roots, driver, {})
    end

    it 'stops after BiDi succeeds' do
      allow(test_instance).to receive(:bidi_session?).and_return(true)
      expect(test_instance).to receive(:expose_closed_shadow_roots_bidi).and_return(true)
      expect(test_instance).to_not receive(:closed_shadow_classic_allowed?)
      call(:expose_closed_shadow_roots, driver, {})
    end

    it 'falls back to classic when CDP and BiDi fail' do
      allow(driver).to receive(:capabilities).and_return(double('caps', browser_name: 'chrome'))
      allow(driver).to receive(:respond_to?).with(:execute_cdp).and_return(true)
      allow(test_instance).to receive(:bidi_session?).and_return(true)
      allow(test_instance).to receive(:expose_closed_shadow_roots_cdp).and_return(false)
      allow(test_instance).to receive(:expose_closed_shadow_roots_bidi).and_return(false)
      allow(test_instance).to receive(:closed_shadow_classic_allowed?).and_return(true)
      expect(test_instance).to receive(:expose_closed_shadow_roots_classic).with(driver)
      call(:expose_closed_shadow_roots, driver, {})
    end

    it 'logs and continues on unexpected errors' do
      allow(test_instance).to receive(:closed_shadow_classic_allowed?)
        .and_raise(StandardError, 'boom')
      expect { call(:expose_closed_shadow_roots, driver, {}) }
        .to output(/Could not expose closed shadow roots: boom/).to_stdout
    end
  end

  describe '#browser_name and #bidi_session?' do
    it 'returns an empty name when capabilities are unavailable' do
      expect(call(:browser_name, Object.new)).to eq('')
    end

    it 'detects a BiDi session only from a string webSocketUrl' do
      allow(driver).to receive(:respond_to?).and_return(true)
      allow(driver).to receive(:capabilities).and_return(web_socket_url: 'wss://x')
      expect(call(:bidi_session?, driver)).to be true
      allow(driver).to receive(:capabilities).and_return('webSocketUrl' => true)
      expect(call(:bidi_session?, driver)).to be false
      allow(driver).to receive(:capabilities).and_raise(StandardError)
      expect(call(:bidi_session?, driver)).to be false
      expect(call(:bidi_session?, Object.new)).to be false
    end
  end

  describe '#expose_closed_shadow_roots_cdp' do
    let(:bridge) { double('bridge') }
    let(:chromium) do
      d = Class.new { include Selenium::WebDriver::DriverExtensions::HasCDP }.new
      d.instance_variable_set(:@bridge, bridge)
      d
    end
    let(:document) do
      {'root' => {'backendNodeId' => 1, 'children' => [
        {'backendNodeId' => 2, 'shadowRoots' => [
          {'backendNodeId' => 3, 'shadowRootType' => 'closed', 'children' => [
            {'backendNodeId' => 4,
             'shadowRoots' => [{'backendNodeId' => 5, 'shadowRootType' => 'closed'}],},
          ],},
        ],},
        {'backendNodeId' => 6,
         'shadowRoots' => [{'backendNodeId' => 7, 'shadowRootType' => 'open'}],},
        {'backendNodeId' => 8, 'contentDocument' => {}, 'shadowRoots' => [
          {'backendNodeId' => 9, 'shadowRootType' => 'closed'},
        ],},
      ],}}
    end

    def cdp(cmd, params = {})
      receive(:send_command).with(cmd: cmd, params: params)
    end

    # Driven through the real HasCDP#execute_cdp so keyword arguments are enforced.
    it 'maps nested closed roots to their hosts via keyword CDP calls' do
      expect(bridge).to cdp('DOM.enable')
      expect(bridge).to cdp('DOM.getDocument', depth: -1, pierce: true).and_return(document)
      [2, 3, 4, 5].each do |id|
        expect(bridge).to cdp('DOM.resolveNode', backendNodeId: id)
          .and_return('object' => {'objectId' => "obj-#{id}"})
      end
      [[2, 3], [4, 5]].each do |host, shadow|
        expect(bridge).to cdp(
          'Runtime.callFunctionOn',
          functionDeclaration: PercyCapybara::CLOSED_SHADOW_SET_FN, objectId: "obj-#{host}",
          arguments: [{objectId: "obj-#{shadow}"}],
        )
      end
      expect(call(:expose_closed_shadow_roots_cdp, chromium)).to be true
    end

    it 'skips unresolvable pairs' do
      allow(bridge).to cdp('DOM.enable')
      allow(bridge).to cdp('DOM.getDocument', depth: -1, pierce: true).and_return(document)
      allow(bridge).to receive(:send_command).with(cmd: 'DOM.resolveNode', params: anything)
        .and_return('object' => {})
      expect(bridge).to_not receive(:send_command)
        .with(cmd: 'Runtime.callFunctionOn', params: anything)
      expect(call(:expose_closed_shadow_roots_cdp, chromium)).to be true
    end

    it 'returns false without a document root' do
      allow(bridge).to cdp('DOM.enable')
      allow(bridge).to cdp('DOM.getDocument', depth: -1, pierce: true).and_return({})
      expect(call(:expose_closed_shadow_roots_cdp, chromium)).to be false
    end

    it 'returns false and logs when CDP fails' do
      stub_const('PercyCapybara::PERCY_DEBUG', true)
      allow(bridge).to receive(:send_command).and_raise(StandardError, 'no cdp')
      expect { expect(call(:expose_closed_shadow_roots_cdp, chromium)).to be false }
        .to output(/via CDP: no cdp/).to_stdout
    end
  end

  describe '#expose_closed_shadow_roots_bidi' do
    let(:ws) { double('ws') }
    # Same signature and body as Selenium's BiDi#send_cmd(method, **params), so
    # a positional Hash raises like it would against the real binding (which
    # the Ruby 2.x CI rows' Selenium predates).
    let(:bidi) do
      Class.new do
        def initialize(ws)
          @ws = ws
        end

        def send_cmd(method, **params)
          @ws.send_cmd(method: method, params: params.compact)['result']
        end
      end.new(ws)
    end

    def node(id, mode = nil)
      root = {'sharedId' => "#{id}-root", 'value' => {'mode' => mode}}
      value = mode ? {'shadowRoot' => root} : {}
      {'type' => 'node', 'sharedId' => id, 'value' => value}
    end

    def success(value)
      {'result' => {'type' => 'success', 'result' => {'type' => 'array', 'value' => value}}}
    end

    before(:each) do
      allow(driver).to receive(:window_handle).and_return('ctx-1')
      allow(driver).to receive(:bidi).and_return(bidi)
    end

    it 'exposes closed roots and recurses into each one' do
      calls = []
      allow(ws).to receive(:send_cmd) do |method:, params:|
        calls << [method, params]
        case calls.length
        when 1 then success([node('h1', 'closed'), node('h2', 'open'), node('h3')])
        when 3 then success([node('h4', 'closed')])
        else success([])
        end
      end

      expect(call(:expose_closed_shadow_roots_bidi, driver)).to be true
      expect(calls.length).to eq(5)
      expect(calls[0][1][:serializationOptions]).to eq(maxDomDepth: 0, includeShadowTree: 'all')
      expect(calls[0][1][:target]).to eq(context: 'ctx-1')
      expect(calls[1][1][:arguments]).to eq([{type: 'array', value: [
        {type: 'array', value: [{sharedId: 'h1'}, {sharedId: 'h1-root'}]},
      ],}])
      expect(calls[2][1][:arguments]).to eq([{sharedId: 'h1-root'}])
      expect(calls[4][1][:arguments]).to eq([{sharedId: 'h4-root'}])
    end

    it 'stops at the host cap' do
      allow(test_instance).to receive(:closed_shadow_max_hosts).and_return(1)
      count = 0
      allow(ws).to receive(:send_cmd) do
        count += 1
        success([node('h1', 'closed')])
      end
      expect(call(:expose_closed_shadow_roots_bidi, driver)).to be true
      expect(count).to eq(2)
    end

    it 'returns false when the script throws' do
      stub_const('PercyCapybara::PERCY_DEBUG', true)
      allow(ws).to receive(:send_cmd).and_return('result' => {'type' => 'exception'})
      expect { expect(call(:expose_closed_shadow_roots_bidi, driver)).to be false }
        .to output(/via BiDi: script.callFunction exception/).to_stdout
    end

    it 'tolerates an empty result' do
      allow(ws).to receive(:send_cmd).and_return('result' => {'type' => 'success'})
      expect(call(:expose_closed_shadow_roots_bidi, driver)).to be true
    end
  end

  describe '#expose_closed_shadow_roots_classic' do
    def host(shadow)
      h = double('host')
      if shadow == :none
        allow(h).to receive(:shadow_root)
          .and_raise(Selenium::WebDriver::Error::WebDriverError, 'no such shadow root')
      else
        allow(h).to receive(:shadow_root).and_return(shadow)
      end
      h
    end

    it 'sets each closed root and walks into it; null roots (Safari) are skipped' do
      root = double('root')
      nested_root = double('nested_root')
      closed = host(root)
      nested = host(nested_root)
      candidates = PercyCapybara::CLASSIC_SHADOW_CANDIDATES_JS
      allow(driver).to receive(:execute_script).with(candidates, nil)
        .and_return([closed, host(:none), host(nil)])
      allow(driver).to receive(:execute_script).with(candidates, root).and_return([nested])
      allow(driver).to receive(:execute_script).with(candidates, nested_root).and_return(nil)
      expect(driver).to receive(:execute_script)
        .with(PercyCapybara::CLASSIC_SHADOW_SET_JS, closed, root)
      expect(driver).to receive(:execute_script)
        .with(PercyCapybara::CLASSIC_SHADOW_SET_JS, nested, nested_root)
      call(:expose_closed_shadow_roots_classic, driver)
    end

    it 'stops at the host cap' do
      stub_const('PercyCapybara::PERCY_DEBUG', true)
      allow(test_instance).to receive(:closed_shadow_max_hosts).and_return(1)
      second = host(:none)
      allow(driver).to receive(:execute_script).and_return([host(:none), second])
      expect(second).to_not receive(:shadow_root)
      expect { call(:expose_closed_shadow_roots_classic, driver) }
        .to output(/stopped at 1 hosts/).to_stdout
    end

    it 'stops at the host cap silently without debug' do
      allow(test_instance).to receive(:closed_shadow_max_hosts).and_return(1)
      allow(driver).to receive(:execute_script).and_return([host(:none), host(:none)])
      expect { call(:expose_closed_shadow_roots_classic, driver) }.to_not output.to_stdout
    end
  end

  describe '#closed_shadow_max_hosts' do
    around(:each) do |example|
      original = ENV['PERCY_CLOSED_SHADOW_MAX_HOSTS']
      example.run
      ENV['PERCY_CLOSED_SHADOW_MAX_HOSTS'] = original
    end

    it 'defaults to 200, honours valid overrides and ignores invalid ones' do
      ENV.delete('PERCY_CLOSED_SHADOW_MAX_HOSTS')
      expect(call(:closed_shadow_max_hosts)).to eq(200)
      ENV['PERCY_CLOSED_SHADOW_MAX_HOSTS'] = '7'
      expect(call(:closed_shadow_max_hosts)).to eq(7)
      ENV['PERCY_CLOSED_SHADOW_MAX_HOSTS'] = '-1'
      expect(call(:closed_shadow_max_hosts)).to eq(200)
      ENV['PERCY_CLOSED_SHADOW_MAX_HOSTS'] = 'lots'
      expect(call(:closed_shadow_max_hosts)).to eq(200)
    end
  end

  describe '#closed_shadow_classic_allowed?' do
    remote_skip = 'closed shadow roots skipped on remote session; start the session with ' \
      'webSocketUrl: true or set PERCY_CLOSED_SHADOW_CLASSIC=true'
    let(:remote_skip_log) { /\A[^\n]*#{Regexp.escape(remote_skip)}\n\z/ }

    around(:each) do |example|
      original = ENV['PERCY_CLOSED_SHADOW_CLASSIC']
      ENV.delete('PERCY_CLOSED_SHADOW_CLASSIC')
      example.run
      ENV['PERCY_CLOSED_SHADOW_CLASSIC'] = original
    end

    def executor(url)
      http = double('http')
      allow(http).to receive(:server_url).and_return(URI(url))
      allow(driver).to receive(:respond_to?).with(:bridge, true).and_return(true)
      allow(driver).to receive(:bridge).and_return(double('bridge', http: http))
    end

    ['http://localhost:9515', 'http://127.0.0.1:4444/wd/hub', 'http://[::1]:9515'].each do |url|
      it "allows local executor #{url}" do
        executor(url)
        expect(call(:closed_shadow_classic_allowed?, driver)).to be true
      end
    end

    it 'skips remote sessions and logs once' do
      executor('https://hub-cloud.browserstack.com/wd/hub')
      expect {
        2.times { expect(call(:closed_shadow_classic_allowed?, driver)).to be false }
      }.to output(remote_skip_log).to_stdout
    end

    it 'treats an unknown or unreadable executor as remote' do
      allow($stdout).to receive(:puts)
      expect(call(:closed_shadow_classic_allowed?, Object.new)).to be false
      allow(driver).to receive(:respond_to?).with(:bridge, true).and_return(true)
      allow(driver).to receive(:bridge).and_raise(StandardError)
      expect(call(:closed_shadow_classic_allowed?, driver)).to be false
    end

    it 'allows remote sessions with PERCY_CLOSED_SHADOW_CLASSIC=true' do
      ENV['PERCY_CLOSED_SHADOW_CLASSIC'] = 'true'
      expect(call(:closed_shadow_classic_allowed?, driver)).to be true
    end
  end
end
