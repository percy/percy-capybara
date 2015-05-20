RSpec.describe Percy::Capybara::Client::Builds do
  let(:capybara_client) { Percy::Capybara::Client.new }

  describe '#current_build' do
    it 'returns the current build or creates a new one' do
      mock_double = double('build')
      expect(capybara_client.client).to receive(:create_build)
        .with(capybara_client.client.config.repo)
        .and_return(mock_double)
        .once

      current_build = capybara_client.current_build
      expect(current_build).to eq(mock_double)
      # Verify that it memoizes the current build by calling it again:
      expect(current_build).to eq(mock_double)
    end
  end
  describe '#build_initialized?' do
    it 'is false before a build is initialized and true afterward' do
      expect(capybara_client.client).to receive(:create_build).and_return(double('build'))
      expect(capybara_client.build_initialized?).to be_falsey

      capybara_client.initialize_build
      expect(capybara_client.build_initialized?).to be_truthy
    end
  end
  describe '#finalize_current_build' do
    it 'finalizes the current build' do
      build_data = {'data' => {'id' => 123}}
      expect(capybara_client.client).to receive(:create_build).and_return(build_data)
      capybara_client.initialize_build

      expect(capybara_client.client).to receive(:finalize_build).with(123)
      capybara_client.finalize_current_build
    end
    it 'raises an error if no current build exists' do
      expect do
        capybara_client.finalize_current_build
      end.to raise_error(Percy::Capybara::Client::BuildNotInitializedError)
    end
  end
end
