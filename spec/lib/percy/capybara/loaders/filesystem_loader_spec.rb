RSpec.describe Percy::Capybara::Loaders::FilesystemLoader do
  let(:fake_page) { OpenStruct.new(current_url: "http://localhost/foo") }
  let(:assets_dir) { File.expand_path("../../client/testdata", __FILE__) }
  let(:loader) { described_class.new(assets_dir:assets_dir, page: fake_page) }

  describe '#snapshot_resources', type: :feature, js: true do
    it 'returns the root HTML' do
      visit '/'
      loader = described_class.new(page: page)
      expect(loader.snapshot_resources.collect(&:resource_url)).to match_array(['/'])
    end
    it 'returns the visited html resource' do
      visit '/test-css.html'
      loader = described_class.new(page: page)
      resource_urls = loader.snapshot_resources.collect(&:resource_url)
      expect(resource_urls).to match_array(['/test-css.html'])
    end
  end

  describe '#build_resources' do
    context 'assets_dir including all test files' do
      it 'returns all included assets as resources' do
        actual_paths = loader.build_resources.collect{|resource| resource.path.gsub(assets_dir,'') }
        expected_paths = [
          '/assets/css/digested-f3420c6aee71c137a3ca39727052811bae84b2f37d898f4db242e20656a1579e.css',
          '/css/base.css',
          '/css/digested.css',
          '/css/imports.css',
          '/css/level0-imports.css',
          '/css/level1-imports.css',
          '/css/level2-imports.css',
          '/css/simple-imports.css',
          '/iframe.html',
          '/images/bg-relative-to-root.png',
          '/images/bg-relative.png',
          '/images/bg-stacked.png',
          '/images/img-relative-to-root.png',
          '/images/img-relative.png',
          '/images/percy.svg',
          '/images/srcset-base.png',
          '/images/srcset-first.png',
          '/images/srcset-second.png',
          '/index.html',
          '/js/base.js',
          '/public/percy-from-public.svg',
          '/test-css.html',
          '/test-iframe.html',
          '/test-images.html',
          '/test-localtest-me-images.html',
        ]
        expect(actual_paths).to eq(expected_paths)
      end
    end
    context 'assets_dir with only skippable resources' do
      let(:assets_dir) { File.expand_path("../../client/testdata/assets/images", __FILE__) }
      it 'returns an empty list' do
        expect(loader.build_resources).to eq([])
      end
    end
  end
end
