RSpec.describe Percy::Capybara do
  before(:each) do
    Percy::Capybara.reset!
    @original_env = ENV['TRAVIS_BUILD_ID']
    ENV['TRAVIS_BUILD_ID'] = nil
  end
  after(:each) do
    ENV['TRAVIS_BUILD_ID'] = @original_env
    ENV.delete('PERCY_ENABLE')
  end

  describe '#capybara_client' do
    it 'returns the current client or creates a new one' do
      capybara_client = Percy::Capybara.capybara_client
      expect(capybara_client).to be
      # Verify that it memoizes the current object by calling it again:
      expect(Percy::Capybara.capybara_client).to eq(capybara_client)
    end
  end
  describe '#snapshot' do
    it 'passes all arguments through to the current capybara_client' do
      mock_page = double('page')
      capybara_client = Percy::Capybara.capybara_client
      expect(capybara_client).to receive(:snapshot).with(mock_page, {}).once
      Percy::Capybara.snapshot(mock_page)
      expect(capybara_client).to receive(:snapshot).with(mock_page, name: '/foo.html (modal)').once
      Percy::Capybara.snapshot(mock_page, name: '/foo.html (modal)')
    end
    it 'silently skips if disabled' do
      ENV['PERCY_ENABLE'] = '0'
      mock_page = double('page')
      Percy::Capybara.snapshot(mock_page)
    end
  end
  describe '#initialize_build' do
    it 'delegates to Percy::Capybara::Client' do
      capybara_client = Percy::Capybara.capybara_client
      expect(capybara_client).to receive(:initialize_build).once
      Percy::Capybara.initialize_build
    end
  end
  describe '#finalize_build' do
    it 'returns silently if no build is initialized' do
      expect { Percy::Capybara.finalize_build }.to_not raise_error
    end
    it 'delegates to Percy::Capybara::Client' do
      capybara_client = Percy::Capybara.capybara_client
      expect(capybara_client).to receive(:enabled?).and_return(:true)
      build_data = {'data' => {'id' => 123}}
      expect(capybara_client.client).to receive(:create_build).and_return(build_data).once
      Percy::Capybara.initialize_build
      expect(capybara_client).to receive(:finalize_current_build).once
      Percy::Capybara.finalize_build
    end
    it 'silently skips if disabled' do
      ENV['PERCY_ENABLE'] = '0'
      capybara_client = Percy::Capybara.capybara_client
      expect(capybara_client.client).to_not receive(:create_build)
      Percy::Capybara.initialize_build
      expect(capybara_client).to_not receive(:finalize_current_build)
      Percy::Capybara.finalize_build
    end
  end
  describe '#reset!' do
    it 'clears the current capybara_client' do
      capybara_client = Percy::Capybara.capybara_client
      Percy::Capybara.reset!
      expect(Percy::Capybara.capybara_client).to_not eq(capybara_client)
    end
  end
  describe '#disable!' do
    it 'sets the current capybara_client to disabled' do
      capybara_client = Percy::Capybara::Client.new(enabled: true)
      expect(Percy::Capybara).to receive(:capybara_client)
        .and_return(capybara_client).exactly(3).times
      expect(Percy::Capybara.capybara_client.enabled?).to eq(true)
      Percy::Capybara.disable!
      expect(Percy::Capybara.capybara_client.enabled?).to eq(false)
    end
  end
  describe '#use_loader' do
    class DummyLoader < Percy::Capybara::Loaders::NativeLoader; end

    it 'sets the current capybara client\'s loader' do
      expect(Percy::Capybara.capybara_client.loader).to_not be
      Percy::Capybara.reset!

      Percy::Capybara.use_loader(DummyLoader)
      expect(Percy::Capybara.capybara_client.loader).to be
    end

    it 'sets the current capybara client\'s loader options' do
      expect(Percy::Capybara.capybara_client.loader_options).to eq({})
      Percy::Capybara.reset!

      Percy::Capybara.use_loader(DummyLoader, test_option: 3)
      expect(Percy::Capybara.capybara_client.loader_options).to be
      expect(Percy::Capybara.capybara_client.loader_options[:test_option]).to eq(3)
    end
  end
end
