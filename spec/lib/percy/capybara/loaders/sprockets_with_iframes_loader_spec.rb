require 'sprockets'

RSpec.describe Percy::Capybara::Loaders::SprocketsWithIframesLoader do
  let(:loader) do
    described_class.new(
      page: page,
      sprockets_environment: environment,
      sprockets_options: sprockets_options
    )
  end
  let(:environment) do
    root = File.expand_path("../../client/testdata", __FILE__)
    environment = Sprockets::Environment.new(root)
    environment.append_path '.'
    environment
  end
  let(:digest_enabled) { false }
  let(:sprockets_options) do
    options = double('options')
    # Set specific files we want to compile. In normal use, this would be all CSS and JS files.
    precompile_list = [/(?:\/|\\|\A)(base|digested)\.(css|js)$|\.map/]
    allow(options).to receive(:precompile).and_return(precompile_list)
    allow(options).to receive(:digest).and_return(digest_enabled)
    options
  end

  describe '#snapshot_resources', type: :feature, js: true do
    before { visit('/test-iframe.html') }

    it 'includes a new iframe resource' do
      last_resource = loader.snapshot_resources.last
      expect(last_resource.resource_url).to eq('iframe.html')
      expect(last_resource.content).to include('Inside iframe')
    end
  end
end
