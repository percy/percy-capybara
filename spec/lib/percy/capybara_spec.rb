RSpec.describe Percy::Capybara do
  before do
    described_class.reset!
    @original_env = ENV['TRAVIS_BUILD_ID']
    ENV['TRAVIS_BUILD_ID'] = nil
  end
  after do
    ENV['TRAVIS_BUILD_ID'] = @original_env
    ENV.delete('PERCY_ENABLE')
  end

  describe '#capybara_client' do
    it 'returns the current client or creates a new one' do
      capybara_client = described_class.capybara_client
      expect(capybara_client).to be
      # Verify that it memoizes the current object by calling it again:
      expect(described_class.capybara_client).to eq(capybara_client)
    end
  end
  describe '#snapshot' do
    it 'passes all arguments through to the current capybara_client' do
      mock_page = double('page')
      capybara_client = described_class.capybara_client
      expect(capybara_client).to receive(:snapshot).with(mock_page, {}).once
      described_class.snapshot(mock_page)
      expect(capybara_client).to receive(:snapshot).with(mock_page, name: '/foo.html (modal)').once
      described_class.snapshot(mock_page, name: '/foo.html (modal)')
    end
    it 'silently skips if disabled' do
      ENV['PERCY_ENABLE'] = '0'
      mock_page = double('page')
      described_class.snapshot(mock_page)
    end
  end
  describe '#initialize_build' do
    it 'delegates to Percy::Capybara::Client' do
      capybara_client = described_class.capybara_client
      expect(capybara_client).to receive(:initialize_build).once
      described_class.initialize_build
    end
  end
  describe '#finalize_build' do
    it 'returns silently if no build is initialized' do
      expect { described_class.finalize_build }.not_to raise_error
    end
    it 'delegates to Percy::Capybara::Client' do
      capybara_client = described_class.capybara_client
      expect(capybara_client).to receive(:enabled?).and_return(:true)
      build_data = { 'data' => { 'id' => 123 } }
      expect(capybara_client.client).to receive(:create_build).and_return(build_data).once
      described_class.initialize_build
      expect(capybara_client).to receive(:finalize_current_build).once
      described_class.finalize_build
    end
    it 'silently skips if disabled' do
      ENV['PERCY_ENABLE'] = '0'
      capybara_client = described_class.capybara_client
      expect(capybara_client.client).not_to receive(:create_build)
      described_class.initialize_build
      expect(capybara_client).not_to receive(:finalize_current_build)
      described_class.finalize_build
    end
  end
  describe '#reset!' do
    it 'clears the current capybara_client' do
      capybara_client = described_class.capybara_client
      described_class.reset!
      expect(described_class.capybara_client).not_to eq(capybara_client)
    end
  end
  describe '#disable!' do
    it 'sets the current capybara_client to disabled' do
      capybara_client = Percy::Capybara::Client.new(enabled: true)
      expect(described_class).to receive(:capybara_client)
        .and_return(capybara_client).exactly(3).times
      expect(described_class.capybara_client.enabled?).to eq(true)
      described_class.disable!
      expect(described_class.capybara_client.enabled?).to eq(false)
    end
  end
  describe '#use_loader' do
    class DummyLoader < Percy::Capybara::Loaders::NativeLoader; end

    it 'sets the current capybara client\'s loader' do
      expect(described_class.capybara_client.loader).not_to be
      described_class.use_loader(DummyLoader)
      expect(described_class.capybara_client.loader).to be
    end

    it 'sets the current capybara client\'s loader options' do
      expect(described_class.capybara_client.loader_options).to eq({})
      described_class.use_loader(DummyLoader, test_option: 3)
      expect(described_class.capybara_client.loader_options).to be
      expect(described_class.capybara_client.loader_options[:test_option]).to eq(3)
    end
  end
end
