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
      config: Percy::Capybara::ConfigLoader.load_default
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
      expected_resources = [
        '/assets/css/base.css',
        '/assets/css/digested.css',
        '/assets/js/base.js',
      ]
      expect(resources.map { |r| r.resource_url }).to eq(expected_resources)
      expect(resources.first.content).to include('.colored-by-base')
    end
    context 'Rails app' do
      before(:each) do
        # Pretend like we're in a Rails app right now, all we care about is Rails.public_path.
        rails_double = double('Rails')
        # Pretend like the entire testdata directory is the public/ folder.
        expect(rails_double).to receive(:public_path).and_return(environment.root)
        expect(loader).to receive(:_rails).at_least(:once).and_return(rails_double)
      end
      it 'includes files from the public folder (non-asset-pipeline)' do
        resources = loader.build_resources
        expect(resources.length).to be > 5  # Weak test that more things are in this list.
        expect(resources.map { |r| r.resource_url }).to include('/images/percy.svg')
      end
      context 'digest enabled' do
        let(:digest_enabled) { true }

        it 'only includes pre-compiled, digested files once' do
          # This makes sure that we correctly merge already-compiled files in the assets directory
          # with ones from the asset pipeline. This means that Rails users who have
          # `config.assets.digest = true` set can safely run "rake assets:precompile" before tests.
          resources = loader.build_resources
          expected_digest_url = \
            '/assets/css/digested-f3420c6aee71c137a3ca39727052811bae84b2f37d898f4db242e20656a1579e.css'
          digested_resources = resources.select { |r| r.resource_url == expected_digest_url }
          expect(digested_resources.length).to eq(1)
        end
      end
      context 'with config set ignored paths' do
        let(:loader) do
          described_class.new(
            page: page,
            sprockets_environment: environment,
            sprockets_options: sprockets_options,
            config: config
          )
        end
        let(:config) do
          {
            'sprockets_loader' => {
              'ignore_paths' => [
                '/images',
                'test-.*\.html'
              ]
            }
          }
        end
        it 'returns "build resources" from filtered sprockets paths' do
          resources = loader.build_resources
          resources_urls = resources.map(&:resource_url)
          expect(resources_urls).not_to include('/images/percy.svg')
          expect(resources_urls).not_to include('/test-images.html')
        end
      end
    end
  end
end
