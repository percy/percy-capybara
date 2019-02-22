RSpec.describe Percy::Capybara do
  subject(:our_module) { Percy::Capybara }

  describe '#environment_info' do
    subject(:environment_info) { Percy::Capybara.environment_info }

    context 'an app with Rails, Sinatra and Ember Cli Rails' do
      it 'returns full environment information' do
        expect(our_module).to receive(:_rails_version).at_least(:once).times.and_return('4.2')
        expect(our_module).to receive(:_sinatra_version).at_least(:once).and_return('2.0.0')
        expect(our_module).to receive(:_ember_cli_rails_version).at_least(:once).and_return('0.9')

        expect(environment_info).to eq('rails/4.2; sinatra/2.0.0; ember-cli-rails/0.9')
      end
    end

    context 'an app with no known frameworks being used' do
      it 'returns unknown environment information' do
        expect(environment_info).to eq('unknown')
      end
    end
  end

  describe '#client_info' do
    subject(:client_info) { Percy::Capybara.client_info }

    it 'includes client information' do
      expect(client_info).to eq("percy-capybara/#{Percy::Capybara::VERSION}")
    end
  end
end
