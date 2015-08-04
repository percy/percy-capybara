RSpec.describe Percy::Capybara::Client::Builds do
  let(:capybara_client) { Percy::Capybara::Client.new(enabled: true) }

  describe '#current_build' do
    it 'returns the current build or creates a new one' do
      mock_double = double('build')
      expect(capybara_client.client).to receive(:create_build)
        .with(capybara_client.client.config.repo, {})
        .and_return(mock_double)
        .once

      current_build = capybara_client.current_build
      expect(current_build).to eq(mock_double)
      # Verify that it memoizes the current build by calling it again:
      expect(current_build).to eq(mock_double)
    end
  end
  describe '#upload_build_resources', type: :feature, js: true do
    before(:each) { setup_sprockets(capybara_client) }

    it 'returns 0 if there are no missing build resources to upload' do
      mock_response = {
        'data' => {
          'id' => '123',
          'type' => 'builds',
        },
      }
      stub_request(:post, 'https://percy.io/api/v1/repos/percy/percy-capybara/builds/')
        .to_return(status: 201, body: mock_response.to_json)

      loader = capybara_client.initialize_loader
      expect(capybara_client.upload_build_resources(loader.build_resources)).to eq(0)
    end
    it 'uploads missing resources and returns the number uploaded' do
      visit '/'
      loader = capybara_client.initialize_loader(page: page)

      mock_response = {
        'data' => {
          'id' => '123',
          'type' => 'builds',
          'relationships' => {
            'self' => "/api/v1/snapshots/123",
            'missing-resources' => {
              'data' => [
                {
                  'type' => 'resources',
                  'id' => loader.build_resources.first.sha,
                },
              ],
            },
          },
        },
      }
      # Stub create build.
      stub_request(:post, 'https://percy.io/api/v1/repos/percy/percy-capybara/builds/')
        .to_return(status: 201, body: mock_response.to_json)
      capybara_client.initialize_build

      # Stub resource upload.
      stub_request(:post, "https://percy.io/api/v1/builds/123/resources/")
        .to_return(status: 201, body: {success: true}.to_json)
      result = capybara_client.upload_build_resources(loader.build_resources)
      expect(result).to eq(1)
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
