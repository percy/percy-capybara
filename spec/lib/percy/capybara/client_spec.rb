RSpec.describe Percy::Capybara::Client do
  it 'accepts and memoizes a client arg' do
    client = Percy::Client.new
    capybara_client = Percy::Capybara::Client.new(client: client)
    expect(capybara_client.client).to eq(client)
  end
  describe '#enabled?' do
    before(:each) do
      @original_env = ENV['TRAVIS_BUILD_ID']
      ENV['TRAVIS_BUILD_ID'] = nil
    end
    after(:each) do
      ENV['TRAVIS_BUILD_ID'] = @original_env
      ENV['PERCY_ENABLE'] = nil
    end

    context 'in supported CI environment' do
      it 'is true' do
        ENV['TRAVIS_BUILD_ID'] = '123'
        expect(Percy::Capybara::Client.new.enabled?).to eq(true)
      end
    end
    it 'is true by default for local dev environments and unknown CI environments' do
      expect(Percy::Capybara::Client.new.enabled?).to eq(true)
    end
    it 'is true if PERCY_ENABLE=1 is set' do
      ENV['PERCY_ENABLE'] = '1'
      expect(Percy::Capybara::Client.new.enabled?).to eq(true)
    end
    it 'is true if PERCY_ENABLE isn\'t set' do
      ENV.delete('PERCY_ENABLE')
      expect(Percy::Capybara::Client.new.enabled?).to eq(true)
    end
    it 'is false if PERCY_ENABLE=0 is set' do
      ENV['PERCY_ENABLE'] = '0'
      expect(Percy::Capybara::Client.new.enabled?).to eq(false)
    end
  end
  describe '#failed?' do
    it 'is false by default' do
      expect(Percy::Capybara::Client.new.failed?).to eq(false)
    end
  end
  describe '#rescue_connection_failures' do
    let(:capybara_client) { Percy::Capybara::Client.new(enabled: true) }
    it 'returns block result on success' do
      result = capybara_client.rescue_connection_failures do
        true
      end
      expect(result).to eq(true)
      expect(capybara_client.enabled?).to eq(true)
      expect(capybara_client.failed?).to eq(false)
    end
    it 'makes block safe from server errors' do
      result = capybara_client.rescue_connection_failures do
        raise Percy::Client::ServerError.new(500, 'POST', '', '')
      end
      expect(result).to eq(nil)
      expect(capybara_client.enabled?).to eq(false)
      expect(capybara_client.failed?).to eq(true)
    end
    it 'makes block safe from quota exceeded errors' do
      result = capybara_client.rescue_connection_failures do
        raise Percy::Client::PaymentRequiredError.new(409, 'POST', '', '')
      end
      expect(result).to eq(nil)
      expect(capybara_client.enabled?).to eq(false)
      expect(capybara_client.failed?).to eq(true)
    end
    it 'makes block safe from ConnectionFailed' do
      result = capybara_client.rescue_connection_failures do
        raise Percy::Client::ConnectionFailed
      end
      expect(result).to eq(nil)
      expect(capybara_client.enabled?).to eq(false)
      expect(capybara_client.failed?).to eq(true)
    end
    it 'makes block safe from TimeoutError' do
      result = capybara_client.rescue_connection_failures do
        raise Percy::Client::TimeoutError
      end
      expect(result).to eq(nil)
      expect(capybara_client.enabled?).to eq(false)
      expect(capybara_client.failed?).to eq(true)
    end
    it 'requires a block' do
      expect { capybara_client.rescue_connection_failures }.to raise_error(ArgumentError)
    end
  end
  describe '#initialize_loader' do
    let(:capybara_client) { Percy::Capybara::Client.new }

    context 'when a custom loader has been set' do
      it 'returns an instance of the clients custom loader' do
        class DummyLoader < Percy::Capybara::Loaders::NativeLoader; end
        capybara_client.custom_loader = DummyLoader
        loader = capybara_client.initialize_loader
        expect(loader.class).to eq(DummyLoader)
      end
    end

    context 'when sprockets is configured' do
      it 'returns a SprocketsLoader' do
        capybara_client.sprockets_environment = double('sprockets_environment')
        capybara_client.sprockets_options = double('sprockets_options')
        loader = capybara_client.initialize_loader
        expect(loader.class).to eq(Percy::Capybara::Loaders::SprocketsLoader)
      end
    end

    context 'when no configuration has been set' do
      it 'returns a NativeLoader' do
        expect(capybara_client.initialize_loader.class).to eq(Percy::Capybara::Loaders::NativeLoader)
      end
    end
  end
end
