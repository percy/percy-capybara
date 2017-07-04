RSpec.describe Percy::Capybara::Loaders::NativeLoader do
  let(:fake_page) { OpenStruct.new(current_url: 'http://localhost/foo') }
  let(:asset_hostnames) { nil }
  let(:loader) do
    Percy::Capybara::Loaders::NativeLoader.new(page: fake_page, asset_hostnames: asset_hostnames)
  end

  describe '#build_resources' do
    it 'returns an empty list' do
      expect(loader.build_resources).to eq([])
    end
  end
  describe '#snapshot_resources', type: :feature, js: true do
    it 'returns the root HTML' do
      visit '/'
      loader = Percy::Capybara::Loaders::NativeLoader.new(page: page)
      expect(loader.snapshot_resources.collect(&:resource_url)).to match_array(['/'])
    end
    it 'returns the root HTML and CSS resources' do
      visit '/test-css.html'
      loader = Percy::Capybara::Loaders::NativeLoader.new(page: page)
      resource_urls = loader.snapshot_resources.collect(&:resource_url)
      expect(resource_urls).to match_array(
        [
          '/test-css.html',
          '/css/base.css',
          '/css/imports.css',
          '/css/level0-imports.css',
          '/css/level1-imports.css',
          '/css/level2-imports.css',
          '/css/simple-imports.css',
        ],
      )
    end
    it 'returns the font resources' do
      visit '/test-font.html'
      loader = Percy::Capybara::Loaders::NativeLoader.new(page: page)
      resource_urls = loader.snapshot_resources.collect(&:resource_url)
      expect(resource_urls).to match_array(
        [
          '/test-font.html',
          '/css/font.css',
          '/assets/bootstrap/glyphicons-halflings-regular-13634da.eot',
        ],
      )
    end
    it 'returns the root HTML and image resources' do
      visit '/test-images.html'
      loader = Percy::Capybara::Loaders::NativeLoader.new(page: page)
      resource_urls = loader.snapshot_resources.collect(&:resource_url)
      expect(resource_urls).to match_array(
        [
          '/test-images.html',
          '/images/img-relative.png',
          '/images/img-relative-to-root.png',
          '/images/percy.svg',
          '/images/srcset-base.png',
          '/images/srcset-first.png',
          '/images/srcset-second.png',
          '/images/bg-relative.png',
          '/images/bg-relative-to-root.png',
          '/images/bg-stacked.png',
        ],
      )
    end
  end
  describe 'nonlocal.me', type: :feature, js: true do
    let(:orig_app_host) { Capybara.app_host }

    before(:each) do
      Capybara.app_host = Capybara.app_host.gsub('http://localhost:', 'http://localtest.me:')
    end
    after(:each) do
      Capybara.app_host = orig_app_host
    end
    it 'returns the root HTML and image resources' do
      visit '/test-localtest-me-images.html'
      loader = Percy::Capybara::Loaders::NativeLoader.new(page: page)
      resource_urls = loader.snapshot_resources.collect(&:resource_url)
      expect(resource_urls).to eq(
        [
          '/test-localtest-me-images.html',
          '/images/img-relative.png',
        ],
      )
      expect(loader.snapshot_resources.collect(&:is_root)).to eq([true, nil])
    end
  end
  describe '#_should_include_url?' do
    it 'returns true for valid, local URLs' do
      expect(loader._should_include_url?('http://localhost/')).to eq(true)
      expect(loader._should_include_url?('http://localhost:123/')).to eq(true)
      expect(loader._should_include_url?('http://localhost/foo')).to eq(true)
      expect(loader._should_include_url?('http://localhost:123/foo')).to eq(true)
      expect(loader._should_include_url?('http://localhost/foo/test.html')).to eq(true)
      expect(loader._should_include_url?('http://127.0.0.1/')).to eq(true)
      expect(loader._should_include_url?('http://127.0.0.1:123/')).to eq(true)
      expect(loader._should_include_url?('http://127.0.0.1/foo')).to eq(true)
      expect(loader._should_include_url?('http://127.0.0.1:123/foo')).to eq(true)
      expect(loader._should_include_url?('http://127.0.0.1/foo/test.html')).to eq(true)
      expect(loader._should_include_url?('http://0.0.0.0/foo/test.html')).to eq(true)
      # Also works for paths:
      expect(loader._should_include_url?('/')).to eq(true)
      expect(loader._should_include_url?('/foo')).to eq(true)
      expect(loader._should_include_url?('/foo/test.png')).to eq(true)
    end
    it 'returns false for invalid URLs' do
      expect(loader._should_include_url?('')).to eq(false)
      expect(loader._should_include_url?('http://local host/foo')).to eq(false)
      expect(loader._should_include_url?('bad-url/')).to eq(false)
      expect(loader._should_include_url?('bad-url/foo/test.html')).to eq(false)
    end
    it 'returns false for data URLs' do
      expect(loader._should_include_url?('data:image/gif;base64,R0')).to eq(false)
    end

    context 'when loader is initialised with asset hostnames' do
      let(:asset_hostnames) { ['dev.local'] }

      context 'with the same port' do
        it 'returns in accordance with asset_hostnames' do
          expect(loader._should_include_url?('http://dev.local/')).to eq(true)
          expect(loader._should_include_url?('http://dev.local/foo')).to eq(true)

          expect(loader._should_include_url?('http://other.local/')).to eq(false)
        end
      end
      context 'with different port' do
        it 'returns in accordance with asset_hostnames' do
          expect(loader._should_include_url?('http://dev.local:4321/foo')).to eq(true)
          expect(loader._should_include_url?('http://other.local:1234/foo')).to eq(false)
        end
      end
      context 'https' do
        it 'returns in accordance with asset_hostnames' do
          expect(loader._should_include_url?('https://dev.local/foo')).to eq(true)
          expect(loader._should_include_url?('https://other.local/foo')).to eq(false)
        end
      end
    end
    context 'for nonlocal hosts' do
      let(:fake_page) { OpenStruct.new(current_url: 'http://foo:123/') }

      it 'returns true for the same host port' do
        expect(loader._should_include_url?('http://foo:123/')).to eq(true)
        expect(loader._should_include_url?('http://foo:123/bar')).to eq(true)
      end
      it 'returns false for different port' do
        expect(loader._should_include_url?('http://foo/')).to eq(false)
        expect(loader._should_include_url?('http://foo/bar')).to eq(false)
        expect(loader._should_include_url?('http://foo:1234/')).to eq(false)
        expect(loader._should_include_url?('http://foo:1234/bar')).to eq(false)
      end
      it 'returns false for different host' do
        expect(loader._should_include_url?('http://afoo:123/')).to eq(false)
        expect(loader._should_include_url?('http://afoo:123/bar')).to eq(false)
      end
    end
  end
  describe '#_get_css_resources', type: :feature, js: true do
    it 'includes all linked and imported stylesheets' do
      visit '/test-css.html'

      loader = Percy::Capybara::Loaders::NativeLoader.new(page: page)
      resources = loader.send(:_get_css_resources)

      resource = find_resource(resources, '/css/base.css')

      expect(resource.content).to include('.colored-by-base { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, '/css/simple-imports.css')
      expect(resource.content).to include("@import url('imports.css');")
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, '/css/imports.css')
      expect(resource.content).to include('.colored-by-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, '/css/level0-imports.css')
      expect(resource.content).to include("@import url('level1-imports.css')")
      expect(resource.content).to include('.colored-by-level0-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, '/css/level1-imports.css')
      expect(resource.content).to include("@import url('level2-imports.css')")
      expect(resource.content).to include('.colored-by-level1-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      resource = find_resource(resources, '/css/level2-imports.css')
      expect(resource.content).to include('.colored-by-level2-imports { color: red; }')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      expect(resources.length).to eq(6)
      expect(resources.collect(&:mimetype).uniq).to eq(['text/css'])
      expect(resources.collect(&:is_root).uniq).to match_array([nil])
    end
  end
  describe '#_get_image_resources', type: :feature, js: true do
    it 'includes all images' do
      visit '/test-images.html'

      loader = Percy::Capybara::Loaders::NativeLoader.new(page: page)
      loader.instance_variable_set(:@urls_referred_by_css, [])
      resources = loader.send(:_get_image_resources)

      # The order of these is just for convenience, they match the order in test-images.html.

      resource = find_resource(resources, '/images/img-relative.png')
      path = File.expand_path('../../client/test_data/images/img-relative.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/img-relative-to-root.png')
      path = File.expand_path('../../client/test_data/images/img-relative-to-root.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/percy.svg')
      path = File.expand_path('../../client/test_data/images/percy.svg', __FILE__)
      content = File.read(path)
      # In Ruby 1.9.3 the SVG mimetype is not registered so our mini ruby webserver doesn't serve
      # the correct content type. Allow either to work here so we can test older Rubies fully.
      expect(resource.mimetype).to match(/image\/svg\+xml|application\/octet-stream/)
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/bg-relative.png')
      path = File.expand_path('../../client/test_data/images/bg-relative.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/bg-relative-to-root.png')
      path = File.expand_path('../../client/test_data/images/bg-relative-to-root.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/bg-stacked.png')
      path = File.expand_path('../../client/test_data/images/bg-stacked.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/srcset-base.png')
      path = File.expand_path('../../client/test_data/images/srcset-base.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/srcset-first.png')
      path = File.expand_path('../../client/test_data/images/srcset-first.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/srcset-second.png')
      path = File.expand_path('../../client/test_data/images/srcset-second.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource_urls = resources.collect(&:resource_url)
      expect(resource_urls).to match_array(
        [
          '/images/img-relative.png',
          '/images/img-relative-to-root.png',
          '/images/percy.svg',
          '/images/srcset-base.png',
          '/images/srcset-first.png',
          '/images/srcset-second.png',
          '/images/bg-relative.png',
          '/images/bg-relative-to-root.png',
          '/images/bg-stacked.png',
        ],
      )
      expect(resources.collect(&:is_root).uniq).to match_array([nil])
    end
  end
end
