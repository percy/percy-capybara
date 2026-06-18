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
      expect(test_instance.send(:unsupported_iframe_src?, 'blob:https://example.com/abc'))
        .to be true
    end

    it 'returns true for vbscript: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'vbscript:msgbox')).to be true
    end

    it 'returns true for chrome: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'chrome://settings')).to be true
    end

    it 'returns true for chrome-extension: URIs' do
      expect(test_instance.send(:unsupported_iframe_src?, 'chrome-extension://abc/popup.html'))
        .to be true
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
      expect(test_instance.send(:get_origin, 'https://example.com/path'))
        .to eq('https://example.com')
    end

    it 'includes non-default port' do
      expect(test_instance.send(:get_origin, 'http://example.com:8080/path'))
        .to eq('http://example.com:8080')
    end

    it 'excludes default http port 80' do
      expect(test_instance.send(:get_origin, 'http://example.com:80/path'))
        .to eq('http://example.com')
    end

    it 'excludes default https port 443' do
      expect(test_instance.send(:get_origin, 'https://example.com:443/path'))
        .to eq('https://example.com')
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
      allow(mock_driver).to receive(:execute_script).and_return(nil, 'html' => '<html></html>')
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
        'html' => '<html>iframe</html>', 'resources' => [], 'warnings' => [],
      )
      allow(mock_frame).to receive(:attribute).with('data-percy-element-id')
        .and_return('percy-id-1')

      result = test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)

      expect(result).to eq(
        'iframeData' => {'percyElementId' => 'percy-id-1'},
        'iframeSnapshot' => {'html' => '<html>iframe</html>', 'resources' => [], 'warnings' => []},
        'frameUrl' => 'https://other.com/embed',
      )
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

    it 'falls back to parent_frame when default_content also fails' do
      switch_to_mock = double('switch_to')
      allow(switch_to_mock).to receive(:frame)
      allow(switch_to_mock).to receive(:default_content).and_raise(StandardError.new('dc gone'))
      expect(switch_to_mock).to receive(:parent_frame)
      allow(mock_driver).to receive(:switch_to).and_return(switch_to_mock)
      allow(mock_driver).to receive(:execute_script).and_return(nil, 'html' => '<x/>')
      allow(mock_frame).to receive(:attribute).with('data-percy-element-id').and_return('id-1')

      test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)
    end

    it 'swallows parent_frame failures when default_content fails too' do
      switch_to_mock = double('switch_to')
      allow(switch_to_mock).to receive(:frame)
      allow(switch_to_mock).to receive(:default_content).and_raise(StandardError.new('dc gone'))
      allow(switch_to_mock).to receive(:parent_frame).and_raise(StandardError.new('pf gone'))
      allow(mock_driver).to receive(:switch_to).and_return(switch_to_mock)
      allow(mock_driver).to receive(:execute_script).and_return(nil, 'html' => '<x/>')
      allow(mock_frame).to receive(:attribute).with('data-percy-element-id').and_return('id-1')

      expect {
        test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)
      }.to_not raise_error
    end

    it 'swallows default_content failures on the outer switch_to rescue path' do
      switch_to_mock = double('switch_to')
      allow(switch_to_mock).to receive(:frame).and_raise(StandardError.new('frame switch failed'))
      allow(switch_to_mock).to receive(:default_content).and_raise(StandardError.new('dc gone'))
      allow(mock_driver).to receive(:switch_to).and_return(switch_to_mock)

      result = test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)
      expect(result).to be_nil
    end

    it 'emits the success-debug log when PERCY_DEBUG is on' do
      stub_const('PercyCapybara::PERCY_DEBUG', true)
      switch_to_mock = double('switch_to')
      allow(switch_to_mock).to receive(:frame)
      allow(switch_to_mock).to receive(:default_content)
      allow(mock_driver).to receive(:switch_to).and_return(switch_to_mock)
      allow(mock_driver).to receive(:execute_script).and_return(nil, 'html' => '<x/>')
      allow(mock_frame).to receive(:attribute).with('data-percy-element-id').and_return('id-1')

      expect {
        test_instance.send(:process_frame, mock_driver, mock_frame, {}, percy_dom_script)
      }.to output(/Successfully captured cross-origin iframe/).to_stdout
    end
  end

  describe '#get_serialized_dom' do
    let(:percy_dom_script) { 'window.PercyDOM = {};' }
    let(:driver) { double('driver') }
    let(:switch_to_mock) { double('switch_to', frame: nil, default_content: nil) }

    def build_page(current_url:, iframes:)
      page = double('page', current_url: current_url, driver: double('cap_driver', browser: driver))
      allow(page).to receive(:evaluate_script).and_return('html' => '<page/>', 'resources' => [])
      allow(driver).to receive(:find_elements).with(:tag_name, 'iframe').and_return(iframes)
      allow(driver).to receive(:switch_to).and_return(switch_to_mock)
      allow(driver).to receive(:execute_script).and_return(nil, 'html' => '<iframe/>')
      page
    end

    def build_iframe(src:, percy_id: 'pid')
      f = double('iframe')
      allow(f).to receive(:attribute).with('src').and_return(src)
      allow(f).to receive(:attribute).with('data-percy-element-id').and_return(percy_id)
      f
    end

    it 'skips unsupported, invalid, and same-origin iframes and captures CORS ones' do
      stub_const('PercyCapybara::PERCY_DEBUG', true)
      page = build_page(
        current_url: 'https://example.com/',
        iframes: [
          build_iframe(src: 'about:blank'),
          build_iframe(src: ':bad uri'),
          build_iframe(src: 'https://example.com/same'),
          build_iframe(src: 'https://other.com/cors'),
        ],
      )

      result = test_instance.send(:get_serialized_dom, page, {}, percy_dom_script)
      expect(result['corsIframes'].length).to eq(1)
      expect(result['corsIframes'][0]['frameUrl']).to eq('https://other.com/cors')
    end

    it 'leaves corsIframes unset when no CORS frame is found' do
      page = build_page(current_url: 'https://example.com/', iframes: [])
      result = test_instance.send(:get_serialized_dom, page, {}, percy_dom_script)
      expect(result).to_not have_key('corsIframes')
    end

    it 'skips CORS iframes that are missing data-percy-element-id pre-flight' do
      stub_const('PercyCapybara::PERCY_DEBUG', true)
      page = build_page(
        current_url: 'https://example.com/',
        iframes: [build_iframe(src: 'https://other.com/cors', percy_id: nil)],
      )
      # process_frame must not be called when the pre-flight check skips the frame
      expect(driver).to_not receive(:switch_to)

      expect {
        result = test_instance.send(:get_serialized_dom, page, {}, percy_dom_script)
        expect(result).to_not have_key('corsIframes')
      }.to output(/no data-percy-element-id found/).to_stdout
    end

    it 'swallows iframe-loop failures and tries to restore default_content' do
      stub_const('PercyCapybara::PERCY_DEBUG', true)
      page = double('page', current_url: 'https://example.com/')
      allow(page).to receive(:evaluate_script).and_return('html' => '<page/>')
      allow(page).to receive(:driver).and_return(double('cap_driver', browser: driver))
      allow(driver).to receive(:find_elements).and_raise(StandardError.new('boom'))
      # Outer rescue tries default_content; let it raise too to cover line 97.
      allow(driver).to receive(:switch_to).and_return(double('s', default_content: nil))
      allow(driver.switch_to).to receive(:default_content).and_raise(StandardError.new('dc gone'))

      expect {
        test_instance.send(:get_serialized_dom, page, {}, percy_dom_script)
      }.to_not raise_error
    end
  end

  describe '#percy_snapshot error propagation' do
    it 'logs when the server returns success: false' do
      stub_const('PercyCapybara::PERCY_DEBUG', true)
      instance = Class.new { include PercyCapybara }.new
      allow(instance).to receive(:percy_enabled?).and_return(true)
      allow(instance).to receive(:fetch_percy_dom)
        .and_return('window.PercyDOM={serialize:function(){return {}}};')
      browser = double('b')
      allow(browser).to receive(:find_elements).and_return([])
      session = double(
        'session',
        current_url: 'https://example.com/',
        evaluate_script: {'html' => '<x/>'},
        driver: double('d', browser: browser),
      )
      allow(Capybara).to receive(:current_session).and_return(session)
      failure_response = instance_double(
        'Net::HTTPResponse',
        body: '{"success":false,"error":"boom"}',
      )
      allow(instance).to receive(:fetch).and_return(failure_response)

      expect {
        instance.percy_snapshot('Name')
      }.to output(/Could not take DOM snapshot/).to_stdout
    end
  end
end
