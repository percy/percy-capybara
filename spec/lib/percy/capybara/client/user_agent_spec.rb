RSpec.describe Percy::Capybara::Client do
  subject(:client) do
    described_class.new(
      enabled: true,
      sprockets_environment: 'test',
      sprockets_options: 'test',
    )
  end

  describe '#_environment_info' do
    subject(:environment_info) { client._environment_info }

    context 'an app with Rails, Sinatra and Ember Cli Rails' do
      before do
        stub_const('Rails', nil)
        stub_const('Sinatra', nil)
        stub_const('EmberCli::VERSION', 0.9)
      end

      it 'returns full environment information' do
        expect(Rails).to receive(:version).and_return('4.2')
        expect(Sinatra).to receive(:version).and_return('2.0.0')

        expect(environment_info).to eq('rails/2.0.0; sinatra/3.1.0; ember-cli-rails/0.9')
      end
    end

    context 'an app with no known frameworks being used' do
      it 'returns full environment information' do
        expect(environment_info).to be_empty
      end
    end

    context 'a loader is configured' do
      before { client.loader = :sprockets_loader }

      it 'includes loader information' do
        expect(environment_info).to eq('percy-capybara-loader/sprockets_loader')
      end
    end
  end

  describe '#_client_info' do
    subject(:client_info) { client._client_info }

    it 'includes client information' do
      expect(client_info).to eq("percy-capybara/#{Percy::Capybara::VERSION}")
    end
  end
end
