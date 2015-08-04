require 'json'
require 'digest'
require 'capybara'
require 'capybara/webkit'

RSpec.describe Percy::Capybara::Client::Snapshots, type: :feature do
  let(:capybara_client) { Percy::Capybara::Client.new(enabled: true) }

  describe '#snapshot', type: :feature, js: true do
    context 'simple page with no resources' do
      before(:each) { setup_sprockets(capybara_client) }

      it 'creates a snapshot and uploads missing build resources and missing snapshot resources' do
        visit '/'
        loader = capybara_client.initialize_loader(page: page)

        build_resource_sha = loader.build_resources.first.sha
        snapshot_resource_sha = loader.snapshot_resources.first.sha

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
                    'id' => build_resource_sha,
                  },
                ],
              },
            },
          },
        }
        stub_request(:post, 'https://percy.io/api/v1/repos/percy/percy-capybara/builds/')
          .to_return(status: 201, body: mock_response.to_json)

        mock_response = {
          'data' => {
            'id' => '256',
            'type' => 'snapshots',
            'relationships' => {
              'self' => "/api/v1/snapshots/123",
              'missing-resources' => {
                'data' => [
                  {
                    'type' => 'resources',
                    'id' => snapshot_resource_sha,
                  },
                ],
              },
            },
          },
        }
        stub_request(:post, 'https://percy.io/api/v1/builds/123/snapshots/')
          .to_return(status: 201, body: mock_response.to_json)
        build_resource_stub = stub_request(:post, "https://percy.io/api/v1/builds/123/resources/")
          .with(body: /#{build_resource_sha}/)
          .to_return(status: 201, body: {success: true}.to_json)
        stub_request(:post, "https://percy.io/api/v1/builds/123/resources/")
          .with(body: /#{snapshot_resource_sha}/)
          .to_return(status: 201, body: {success: true}.to_json)
        stub_request(:post, "https://percy.io/api/v1/snapshots/256/finalize")
          .to_return(status: 200, body: '{"success":true}')

        expect(capybara_client.build_initialized?).to eq(false)
        expect(capybara_client.snapshot(page)).to eq(true)
        expect(capybara_client.build_initialized?).to eq(true)

        # Second time, no build resources are uploaded.
        remove_request_stub(build_resource_stub)
        expect(capybara_client.snapshot(page)).to eq(true)
      end
    end
  end
end
