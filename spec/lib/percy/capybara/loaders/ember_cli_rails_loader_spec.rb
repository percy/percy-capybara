RSpec.describe Percy::Capybara::Loaders::EmberCliRailsLoader do
  let(:assets_dir) { File.expand_path('../../client/ember_test_data', __FILE__) }
  let(:mounted_apps) { {frontend: ''} }
  let(:digest_enabled) { false }

  let(:environment) do
    environment = Sprockets::Environment.new(assets_dir)
    environment.append_path '.'
    environment
  end

  let(:loader) do
    described_class.new(
      mounted_apps, sprockets_environment: environment, sprockets_options: sprockets_options,
    )
  end

  let(:sprockets_options) do
    options = double('options')
    # Set specific files we want to compile. In normal use, this would be all asset files.
    # For this test we just use .svg files
    precompile_list = [%r{(?:/|\\|\A)\.svg}]
    allow(options).to receive(:precompile).and_return(precompile_list)
    allow(options).to receive(:digest).and_return(digest_enabled)
    options
  end

  describe 'initialize' do
    context 'all args supplied' do
      it 'successfully initializes' do
        expect { loader }.not_to raise_error
      end
    end

    context 'mounted_apps not specified' do
      let(:mounted_apps) { nil }

      it 'raises an error' do
        expect { loader }.to raise_error(StandardError)
      end
    end
  end

  describe '#build_resources' do
    shared_examples 'a mounted ember app' do |mounted_apps|
      ember_app  = mounted_apps.keys.first
      mount_path = mounted_apps.values.first

      let(:ember_app) { ember_app }
      let(:mount_path) { mounted_apps.values.first }
      let(:dist_dir) { File.join(assets_dir, 'ember-cli', ember_app.to_s) }

      context "called '#{ember_app}' and mounted at '#{mount_path}'" do
        it 'builds the expected resources' do
          loader = described_class.new(mounted_apps, sprockets_environment: environment,
                                                     sprockets_options: sprockets_options)
          allow(loader).to receive(:_dist_path_for_app).and_return(dist_dir)

          expected_urls = loader.build_resources.collect(&:resource_url)
          expected_url  = loader._uri_join(mount_path, described_class::EMBER_ASSETS_DIR,
                                           "percy-#{ember_app}.svg")

          expect(expected_urls).to include(expected_url)
        end
      end
    end

    it_behaves_like 'a mounted ember app', {frontend: '/'}
    it_behaves_like 'a mounted ember app', {frontend: ''}
    it_behaves_like 'a mounted ember app', {admin: '/admin'}
    it_behaves_like 'a mounted ember app', {admin: '/admin/'}
  end
end
