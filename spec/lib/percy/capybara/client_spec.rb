RSpec.describe Percy::Capybara::Client do
  describe '#enabled?' do
    context 'when required environment variables set' do
      before(:each) { set_required_env_variables }
      after(:each) { clear_percy_env_variables }

      it 'is true when PERCY_ENABLE is 1' do
        ENV['PERCY_ENABLE'] = '1'
        expect(Percy::Capybara::Client.new.enabled?).to eq(true)
      end

      it 'is true when PERCY_ENABLE is not set' do
        ENV.delete 'PERCY_ENABLE'
        expect(Percy::Capybara::Client.new.enabled?).to eq(true)
      end

      it 'is false when PERCY_ENABLE is 0' do
        ENV['PERCY_ENABLE'] = '0'
        expect(Percy::Capybara::Client.new.enabled?).to eq(false)
      end

      it 'raises error if PERCY_TOKEN is set but PERCY_PROJECT is not' do
        ENV.delete 'PERCY_PROJECT'
        expect { Percy::Capybara::Client.new.enabled? }.to raise_error(RuntimeError)
      end
    end

    context 'when required environment variables not set' do
      before(:each) { clear_percy_env_variables }

      it 'is false' do
        ENV.delete 'PERCY_ENABLE'
        expect(Percy::Capybara::Client.new.enabled?).to eq(false)
      end

      it 'is false when PERCY_ENABLE is 1' do
        ENV['PERCY_ENABLE'] = '1'
        expect(Percy::Capybara::Client.new.enabled?).to eq(false)
      end
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
      result = capybara_client.rescue_connection_failures { true }

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

  describe '#initialize' do
    let(:capybara_client) { Percy::Capybara::Client.new }

    it 'accepts and memoizes a client arg' do
      client = Percy::Client.new
      capybara_client = Percy::Capybara::Client.new(client: client)
      expect(capybara_client.client).to eq(client)
    end

    it 'passes client info down to the lower level Percy client' do
      expect(capybara_client.client.client_info).to eq("percy-capybara/#{Percy::Capybara::VERSION}")
    end
  end

  describe '#initialize_loader' do
    let(:capybara_client) { Percy::Capybara::Client.new }

    context 'when loader has been set to :native' do
      it 'returns a NativeLoader' do
        capybara_client.loader = :native
        loader = capybara_client.initialize_loader
        expect(loader.class).to eq(Percy::Capybara::Loaders::NativeLoader)
      end
    end

    context 'when loader has been set to :filesystem' do
      it 'returns a FilesystemLoader' do
        capybara_client.loader = :filesystem
        capybara_client.loader_options = {assets_dir: '/', base_url: '/'}
        loader = capybara_client.initialize_loader
        expect(loader.class).to eq(Percy::Capybara::Loaders::FilesystemLoader)
      end
    end

    context 'when loader has been set to a class' do
      it 'returns an instance of the clients custom loader' do
        class DummyLoader < Percy::Capybara::Loaders::NativeLoader; end
        capybara_client.loader = DummyLoader
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
        expect(capybara_client.initialize_loader.class)
          .to eq(Percy::Capybara::Loaders::NativeLoader)
      end
    end

    context 'when loader_options are set' do
      let(:loader_class) { Percy::Capybara::Loaders::FilesystemLoader }
      let(:options) { {assets_dir: 'xyz'} }

      it 'initializes the loader with them' do
        capybara_client.loader = :filesystem
        capybara_client.loader_options = options
        expect(loader_class).to receive(:new).with(options).once
        capybara_client.initialize_loader
      end
    end
  end
end
