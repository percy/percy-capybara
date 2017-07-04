RSpec.describe Percy::Capybara::Client::Builds do
  let(:enabled) { true }
  let(:capybara_client) { Percy::Capybara::Client.new(enabled: enabled) }
  let(:builds_api_url) do
    "https://percy.io/api/v1/repos/#{Percy::Client::Environment.repo}/builds/"
  end

  describe '#initialize_build', type: :feature, js: true do
    before(:each) { setup_sprockets(capybara_client) }

    context 'percy is not enabled' do
      let(:enabled) { false }

      it 'returns nil if not enabled' do
        expect(capybara_client.initialize_build).to be_nil
      end
    end
    it 'initializes and returns a build' do
      mock_response = {
        'data' => {
          'id' => '123',
          'type' => 'builds',
        },
      }
      stub_request(:post, builds_api_url)
        .to_return(status: 201, body: mock_response.to_json)
      expect(capybara_client.initialize_build).to eq(mock_response)
    end
    it 'uploads missing build resources' do
      visit '/'
      loader = capybara_client.initialize_loader(page: page)
      mock_response = {
        'data' => {
          'id' => '123',
          'type' => 'builds',
          'relationships' => {
            'self' => '/api/v1/snapshots/123',
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
      build_stub = stub_request(:post, builds_api_url)
        .to_return(status: 201, body: mock_response.to_json)

      # Stub resource upload.
      resources_stub = stub_request(:post, 'https://percy.io/api/v1/builds/123/resources/')
        .to_return(status: 201, body: {success: true}.to_json)
      capybara_client.initialize_build

      expect(resources_stub).to have_been_requested
      expect(build_stub).to have_been_requested
    end
    it 'safely handles connection errors when creating build' do
      expect(capybara_client.client).to receive(:create_build)
        .and_raise(Percy::Client::ConnectionFailed)
      expect(capybara_client.initialize_build).to eq(nil)
      expect(capybara_client.failed?).to eq(true)
    end
    it 'safely handles connection errors when uploading missing build_resources' do
      visit '/'
      loader = capybara_client.initialize_loader(page: page)
      mock_response = {
        'data' => {
          'id' => '123',
          'type' => 'builds',
          'relationships' => {
            'self' => '/api/v1/snapshots/123',
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
      build_stub = stub_request(:post, builds_api_url)
        .to_return(status: 201, body: mock_response.to_json)

      # Stub resource upload.
      expect(capybara_client.client).to receive(:upload_resource)
        .and_raise(Percy::Client::ConnectionFailed)

      expect(capybara_client.initialize_build).to eq(nil)
      expect(capybara_client.failed?).to eq(true)
      expect(build_stub).to have_been_requested
    end
  end
  describe '#current_build' do
    it 'returns nil if no build has been initialized' do
      expect(capybara_client.current_build).to be_nil
    end
    it 'returns the current build' do
      mock_double = double('build')
      expect(capybara_client.client).to receive(:create_build)
        .with(capybara_client.client.config.repo, {})
        .and_return(mock_double)
        .once
      capybara_client.initialize_build

      current_build = capybara_client.current_build
      expect(current_build).to eq(mock_double)
      # Verify that it memoizes the current build by calling it again:
      expect(current_build).to eq(mock_double)
    end
  end
  describe '#build_initialized?' do
    it 'is false before a build is initialized and true afterward' do
      expect(capybara_client.client).to receive(:create_build).and_return(double('build'))
      expect(capybara_client.build_initialized?).to eq(false)

      capybara_client.initialize_build
      expect(capybara_client.build_initialized?).to eq(true)
    end
  end
  describe '#finalize_current_build' do
    let(:build_data) do
      {'data' => {'id' => 123, 'attributes' => {'web-url' => 'http://localhost/'}}}
    end

    it 'finalizes the current build' do
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
    it 'safely handles connection errors' do
      expect(capybara_client.client).to receive(:create_build).and_return(build_data)
      capybara_client.initialize_build

      expect(capybara_client.client).to receive(:finalize_build)
        .and_raise(Percy::Client::ConnectionFailed)
      expect(capybara_client.finalize_current_build).to eq(nil)
      expect(capybara_client.failed?).to eq(true)
    end
  end
  describe '#_upload_missing_build_resources', type: :feature, js: true do
    before(:each) { setup_sprockets(capybara_client) }

    it 'returns 0 if there are no missing build resources to upload' do
      mock_response = {
        'data' => {
          'id' => '123',
          'type' => 'builds',
        },
      }
      stub_request(:post, builds_api_url)
        .to_return(status: 201, body: mock_response.to_json)
      capybara_client.initialize_build

      loader = capybara_client.initialize_loader
      result = capybara_client.send(:_upload_missing_build_resources, loader.build_resources)
      expect(result).to eq(0)
    end
  end
end
