RSpec.describe Percy::Capybara::Loaders::FilesystemLoader do
  let(:fake_page) { OpenStruct.new(current_url: 'http://localhost/foo') }
  let(:assets_dir) { File.expand_path('../../client/test_data', __FILE__) }
  let(:base_url) { '/url-prefix/' }
  let(:loader) do
    Percy::Capybara::Loaders::FilesystemLoader.new(
      base_url: base_url,
      assets_dir: assets_dir,
      page: fake_page,
    )
  end

  describe 'initialize' do
    context 'assets_dir not specified' do
      let(:assets_dir) { nil }

      it 'raises an error' do
        expect { loader }.to raise_error(ArgumentError)
      end
    end
    context 'assets_dir is not an absolute path' do
      let(:assets_dir) { '../../client/test_data' }

      it 'raises an error' do
        expect { loader }.to raise_error(ArgumentError)
      end
    end
    context "assets_dir doesn't exist" do
      let(:assets_dir) { File.expand_path('../../client/test-data-doesnt-exist', __FILE__) }

      it 'raises an error' do
        expect { loader }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#snapshot_resources', type: :feature, js: true do
    it 'returns the root HTML' do
      visit '/'
      loader = Percy::Capybara::Loaders::FilesystemLoader.new(
        base_url: base_url,
        assets_dir: assets_dir,
        page: page,
      )
      expect(loader.snapshot_resources.collect(&:resource_url)).to match_array(['/'])
    end
    it 'returns the visited html resource' do
      visit '/test-css.html'
      loader = Percy::Capybara::Loaders::FilesystemLoader.new(
        base_url: base_url,
        assets_dir: assets_dir,
        page: page,
      )
      resource_urls = loader.snapshot_resources.collect(&:resource_url)
      expect(resource_urls).to match_array(['/test-css.html'])
    end
  end

  describe '#build_resources' do
    context 'assets_dir including all test files' do
      it 'returns all included assets as resources' do
        actual_paths = loader.build_resources.collect do |resource|
          resource.path.gsub(assets_dir, '')
        end
        expected_paths = [
          '/assets/css/digested-f3420c6aee71c137a3ca39727052811ba' \
            'e84b2f37d898f4db242e20656a1579e.css',
          '/css/base.css',
          '/css/font.css',
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
          '/test-css.html',
          '/test-font.html',
          '/test-iframe.html',
          '/test-images.html',
          '/test-localtest-me-images.html',
        ]
        expect(actual_paths).to match_array(expected_paths)

        expected_urls = loader.build_resources.collect(&:resource_url)
        actual_urls = [
          '/url-prefix/assets/css/digested-f3420c6aee71c137a3ca' \
            '39727052811bae84b2f37d898f4db242e20656a1579e.css',
          '/url-prefix/css/base.css',
          '/url-prefix/css/digested.css',
          '/url-prefix/css/imports.css',
          '/url-prefix/css/level0-imports.css',
          '/url-prefix/css/level1-imports.css',
          '/url-prefix/css/level2-imports.css',
          '/url-prefix/css/simple-imports.css',
          '/url-prefix/css/font.css',
          '/url-prefix/iframe.html',
          '/url-prefix/images/bg-relative-to-root.png',
          '/url-prefix/images/bg-relative.png',
          '/url-prefix/images/bg-stacked.png',
          '/url-prefix/images/img-relative-to-root.png',
          '/url-prefix/images/img-relative.png',
          '/url-prefix/images/percy.svg',
          '/url-prefix/images/srcset-base.png',
          '/url-prefix/images/srcset-first.png',
          '/url-prefix/images/srcset-second.png',
          '/url-prefix/index.html',
          '/url-prefix/js/base.js',
          '/url-prefix/test-css.html',
          '/url-prefix/test-font.html',
          '/url-prefix/test-iframe.html',
          '/url-prefix/test-images.html',
          '/url-prefix/test-localtest-me-images.html',
        ]
        expect(actual_urls).to match_array(expected_urls)
      end
      it 'works with different base_url configs' do
        loader = Percy::Capybara::Loaders::FilesystemLoader.new(
          base_url: '/url-prefix/',
          assets_dir: assets_dir,
        )
        expected_urls = loader.build_resources.collect(&:resource_url)
        expect(expected_urls).to include('/url-prefix/css/font.css')

        loader = Percy::Capybara::Loaders::FilesystemLoader.new(
          base_url: '/url-prefix',
          assets_dir: assets_dir,
        )
        expected_urls = loader.build_resources.collect(&:resource_url)
        expect(expected_urls).to include('/url-prefix/css/font.css')

        loader = Percy::Capybara::Loaders::FilesystemLoader.new(
          base_url: '/',
          assets_dir: assets_dir,
        )
        expected_urls = loader.build_resources.collect(&:resource_url)
        expect(expected_urls).to include('/css/font.css')

        loader = Percy::Capybara::Loaders::FilesystemLoader.new(
          base_url: '',
          assets_dir: assets_dir,
        )
        expected_urls = loader.build_resources.collect(&:resource_url)
        expect(expected_urls).to include('/css/font.css')
      end
    end
    context 'assets_dir with only skippable resources' do
      let(:assets_dir) { File.expand_path('../../client/test_data/assets/images', __FILE__) }

      it 'returns an empty list' do
        expect(loader.build_resources).to eq([])
      end
    end
  end
end
