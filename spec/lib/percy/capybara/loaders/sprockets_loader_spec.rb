require 'sprockets'

class SimpleRackApp
  def self.call(_env)
    [200, {}, 'Hello World']
  end
end

RSpec.describe Percy::Capybara::Loaders::SprocketsLoader do
  let(:test_data_path) do
    File.expand_path('../../client/test_data', __FILE__)
  end
  let(:rails_public_test_data_path) do
    File.expand_path('../../client/rails_public_test_data', __FILE__)
  end
  let(:loader) do
    Percy::Capybara::Loaders::SprocketsLoader.new(
      page: page,
      sprockets_environment: environment,
      sprockets_options: sprockets_options,
    )
  end
  let(:environment) do
    environment = Sprockets::Environment.new(test_data_path)
    environment.append_path '.'
    environment
  end
  let(:digest_enabled) { false }
  let(:sprockets_options) do
    options = double('options')
    # Set specific files we want to compile. In normal use, this would be all asset files.
    precompile_list = [/(?:\/|\\|\A)(base|digested)\.(css|js)$|\.map|\.png/]
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
        expect(resources.map(&:resource_url)).to eq(['/'])
        expect(resources.first.is_root).to eq(true)
        expect(resources.first.content).to include('Hello World')
      end
    end
    context 'Capybara::Poltergeist', type: :feature, js: true do
      it 'returns the root HTML resource' do
        visit '/'
        resources = loader.snapshot_resources
        expect(resources.map(&:resource_url)).to eq(['/'])
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
        '/assets/images/bg-relative-to-root.png',
        '/assets/images/bg-relative.png',
        '/assets/images/bg-stacked.png',
        '/assets/images/img-relative-to-root.png',
        '/assets/images/img-relative.png',
        # '/assets/images/large-file-skipped.png',  # Note: intentionally missing.
        '/assets/images/srcset-base.png',
        '/assets/images/srcset-first.png',
        '/assets/images/srcset-second.png',
        '/assets/js/base.js',
      ]
      expect(resources.map(&:resource_url)).to eq(expected_resources)
      expect(resources.first.content).to include('.colored-by-base')
    end
    context 'Rails app' do
      before(:each) do
        # Pretend like we're in a Rails app right now, all we care about is Rails.public_path.
        rails_double = double('Rails')
        # Pretend like the entire test_data directory is the public/ folder.
        expect(rails_double).to receive(:application).and_return(nil)
        expect(rails_double).to receive(:public_path).and_return(rails_public_test_data_path)
        expect(loader).to receive(:_rails).at_least(:once).and_return(rails_double)
      end
      it 'includes files from the public folder (non-asset-pipeline)' do
        resources = loader.build_resources
        # Weak test that more things are in this list, because it merges asset pipeline with public.
        expect(resources.length).to be > 5

        resource_urls = resources.map(&:resource_url)
        expect(resource_urls).to include('/assets/images/bg-relative.png') # From asset pipeline.
        expect(resource_urls).to include('/percy-from-public.svg') # Public merged into root.
        expect(resource_urls).to include('/symlink_to_images/test.png') # Symlink in public dir.
        expect(resource_urls).to_not include('/large-file-skipped.png') # Public merged into root.
      end
      context 'digest enabled' do
        let(:digest_enabled) { true }

        it 'only includes pre-compiled, digested files once' do
          # This makes sure that we correctly merge already-compiled files in the assets directory
          # with ones from the asset pipeline. This means that Rails users who have
          # `config.assets.digest = true` set can safely run "rake assets:precompile" before tests.
          resources = loader.build_resources
          expected_digest_url = \
            '/assets/css/digested-f3420c6aee71c137a3ca39727052811bae84b2f37' \
            'd898f4db242e20656a1579e.css'
          digested_resources = resources.select { |r| r.resource_url == expected_digest_url }
          expect(digested_resources.length).to eq(1)
        end
      end
    end
  end
end
