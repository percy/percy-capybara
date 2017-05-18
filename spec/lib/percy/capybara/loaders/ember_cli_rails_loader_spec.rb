RSpec.describe Percy::Capybara::Loaders::EmberCliRailsLoader do
  let(:fake_page) { OpenStruct.new(current_url: 'http://localhost/foo') }
  let(:assets_dir) { File.expand_path('../../client/testdata', __FILE__) }
  let(:base_url) { '/url-prefix/' }
  let(:mounted_apps) { { frontend: '' } }
  let(:loader) do
    described_class.new(
      mounted_apps,
      { base_url:   base_url,
        assets_dir: assets_dir,
        page:       fake_page })
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
end
