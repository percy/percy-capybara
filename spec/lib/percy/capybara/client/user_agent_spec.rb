RSpec.describe Percy::Capybara::Client::UserAgent do
  subject(:client) do
    Percy::Capybara::Client.new(
      enabled: true,
      sprockets_environment: 'test',
      sprockets_options: 'test',
    )
  end

  describe '#_environment_info' do
    subject(:environment_info) { client._environment_info }

    context 'an app with Rails, Sinatra and Ember Cli Rails' do
      it 'returns full environment information' do
        expect(client).to receive(:_rails_version).at_least(:once).times.and_return('4.2')
        expect(client).to receive(:_sinatra_version).at_least(:once).and_return('2.0.0')
        expect(client).to receive(:_ember_cli_rails_version).at_least(:once).and_return('0.9')

        expect(environment_info).to eq('rails/4.2; sinatra/2.0.0; ember-cli-rails/0.9')
      end
    end

    context 'an app with no known frameworks being used' do
      it 'returns no environment information' do
        expect(environment_info).to be_empty
      end
    end

    context 'a loader is configured' do
      before(:each) { client.loader = :sprockets_loader }

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
