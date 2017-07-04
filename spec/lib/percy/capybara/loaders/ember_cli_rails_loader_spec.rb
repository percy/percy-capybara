require 'set'

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
    Percy::Capybara::Loaders::EmberCliRailsLoader.new(
      mounted_apps,
      sprockets_environment: environment,
      sprockets_options: sprockets_options,
    )
  end

  let(:sprockets_options) do
    options = instance_double('options')
    # Set specific files we want to compile. In normal use, this would be all asset files.
    # For this test we just use .svg files
    precompile_list = [/(?:\/|\\|\A)\.svg/]
    allow(options).to receive(:precompile).and_return(precompile_list)
    allow(options).to receive(:digest).and_return(digest_enabled)
    options
  end

  describe 'initialize' do
    context 'all args supplied' do
      it 'successfully initializes' do
        expect { loader }.to_not raise_error
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
      let(:loader) do
        Percy::Capybara::Loaders::EmberCliRailsLoader.new(
          mounted_apps,
          sprockets_environment: environment,
          sprockets_options: sprockets_options,
        )
      end

      context "called '#{ember_app}' and mounted at '#{mount_path}'" do
        before(:each) do
          allow(loader).to receive(:_dist_path_for_app).and_return(dist_dir)
        end

        it 'builds the expected resources' do
          built_urls = Set.new(loader.build_resources.collect(&:resource_url))

          expected_urls = Set.new
          expected_urls << loader._uri_join(mount_path, "/assets/percy-#{ember_app}.svg")
          expected_urls << loader._uri_join(mount_path, "/percy-#{ember_app}-public.svg")

          expect(expected_urls.subset?(built_urls)).to be true
        end
      end
    end

    it_behaves_like 'a mounted ember app', frontend: '/'
    it_behaves_like 'a mounted ember app', frontend: ''
    it_behaves_like 'a mounted ember app', admin: '/admin'
    it_behaves_like 'a mounted ember app', admin: '/admin/'
  end
end
