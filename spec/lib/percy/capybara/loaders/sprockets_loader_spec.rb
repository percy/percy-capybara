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
    allow(options).to receive(:precompile).and_return([/(?:\/|\\|\A)base\.(css|js)$/])
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
  end
end
