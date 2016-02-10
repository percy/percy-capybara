require 'sprockets'

class SimpleRackApp
  def self.call(env)
    [200, {}, 'Hello World']
  end
end

RSpec.describe Percy::Capybara::Loaders::SprocketsLoader do
  let(:loader) do
    described_class.new(
      page: page,
      sprockets_environment: environment,
      sprockets_options: sprockets_options,
    )
  end
  let(:environment) do
    root = File.expand_path("../../client/testdata", __FILE__)
    environment = Sprockets::Environment.new(root)
    environment.append_path '.'
    environment
  end
  let(:sprockets_options) do
    options = double('options')
    allow(options).to receive(:precompile).and_return([/(?:\/|\\|\A)base\.(css|js)$|\.map/])
    allow(options).to receive(:digest).and_return(false)
    options
  end

  describe '#snapshot_resources' do
    context 'Rack::Test', type: :feature do
      before(:each) { Capybara.app = SimpleRackApp }

      it 'returns the root HTML resource' do
        visit '/'
        resources = loader.snapshot_resources
        expect(resources.map { |r| r.resource_url }).to eq(["/"])
        expect(resources.first.is_root).to eq(true)
        expect(resources.first.content).to include('Hello World')
      end
    end
    context 'Capybara::Webkit', type: :feature, js: true do
      it 'returns the root HTML resource' do
        visit '/'
        resources = loader.snapshot_resources
        expect(resources.map { |r| r.resource_url }).to eq(["/"])
        expect(resources.first.is_root).to eq(true)
        expect(resources.first.content).to include('Hello World!</body></html>')
      end
    end
  end
  describe '#build_resources', type: :feature do
    it 'returns "build resources" from filtered sprockets paths' do
      resources = loader.build_resources
      expect(resources.map { |r| r.resource_url }).to eq(["/assets/css/base.css"])
      expect(resources.first.content).to include('.colored-by-base')
    end
    context 'Rails app' do
      it 'includes files from the public folder (non-asset-pipeline)' do

        # Pretend like we're in a Rails app right now, all we care about is Rails.public_path.
        rails_double = double('Rails')
        # Pretend like the entire testdata directory is the public/ folder.
        expect(rails_double).to receive(:public_path).and_return(environment.root)
        expect(loader).to receive(:_rails).at_least(:once).and_return(rails_double)

        resources = loader.build_resources
        expect(resources.length).to be > 5  # Weak test that more things are in this list.
        expect(resources.map { |r| r.resource_url }).to include('/images/percy.svg')
      end
    end
  end
end
