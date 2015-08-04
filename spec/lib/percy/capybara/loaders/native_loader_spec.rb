RSpec.describe Percy::Capybara::Loaders::NativeLoader do
  let(:loader) { described_class.new(page: nil) }

  describe '#build_resources' do
    it 'returns an empty list' do
      expect(loader.build_resources).to eq([])
    end
  end
  describe '#snapshot_resources', type: :feature, js: true do
    it 'returns the root HTML' do
      visit '/'
      loader = described_class.new(page: page)
      expect(loader.snapshot_resources.collect(&:resource_url)).to match_array(['/'])
    end
    it 'returns the root HTML and CSS resources' do
      visit '/test-css.html'
      loader = described_class.new(page: page)
      resource_urls = loader.snapshot_resources.collect(&:resource_url).map do |url|
        url.gsub(/localhost:\d+/, 'localhost')
      end
      expect(resource_urls).to match_array([
        "/test-css.html",
        "http://localhost/css/base.css",
        "http://localhost/css/imports.css",
        "http://localhost/css/level0-imports.css",
        "http://localhost/css/level1-imports.css",
        "http://localhost/css/level2-imports.css",
        "http://localhost/css/simple-imports.css",
      ])
    end
    it 'returns the root HTML and image resources' do
      visit '/test-images.html'
      loader = described_class.new(page: page)
      resource_urls = loader.snapshot_resources.collect(&:resource_url).map do |url|
        url.gsub(/localhost:\d+/, 'localhost')
      end
      expect(resource_urls).to match_array([
        "/test-images.html",
        "http://localhost/images/img-relative.png",
        "http://localhost/images/img-relative-to-root.png",
        "http://localhost/images/percy.svg",
        "http://localhost/images/srcset-base.png",
        "http://localhost/images/srcset-first.png",
        "http://localhost/images/srcset-second.png",
        "http://localhost/images/bg-relative.png",
        "http://localhost/images/bg-relative-to-root.png",
        "http://localhost/images/bg-stacked.png"
      ])
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
    it 'returns false for remote URLs' do
      expect(loader._should_include_url?('http://foo/')).to eq(false)
      expect(loader._should_include_url?('http://example.com/')).to eq(false)
      expect(loader._should_include_url?('http://example.com/foo')).to eq(false)
      expect(loader._should_include_url?('https://example.com/foo')).to eq(false)
    end
  end
  describe '#_get_css_resources', type: :feature, js: true do
    it 'includes all linked and imported stylesheets' do
      visit '/test-css.html'

      loader = described_class.new(page: page)
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
      expect(resource.content).to include(".colored-by-level2-imports { color: red; }")
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))

      expect(resources.length).to eq(6)
      expect(resources.collect(&:mimetype).uniq).to eq(['text/css'])
      expect(resources.collect(&:is_root).uniq).to match_array([nil])
    end
  end
  describe '#_get_image_resources', type: :feature, js: true do
    it 'includes all images' do
      visit '/test-images.html'

      loader = described_class.new(page: page)
      resources = loader.send(:_get_image_resources)

      # The order of these is just for convenience, they match the order in test-images.html.

      resource = find_resource(resources, '/images/img-relative.png')
      path = File.expand_path('../../client/testdata/images/img-relative.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/img-relative-to-root.png')
      path = File.expand_path('../../client/testdata/images/img-relative-to-root.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/percy.svg')
      path = File.expand_path('../../client/testdata/images/percy.svg', __FILE__)
      content = File.read(path)
      # In Ruby 1.9.3 the SVG mimetype is not registered so our mini ruby webserver doesn't serve
      # the correct content type. Allow either to work here so we can test older Rubies fully.
      expect(resource.mimetype).to match(/image\/svg\+xml|application\/octet-stream/)
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/bg-relative.png')
      path = File.expand_path('../../client/testdata/images/bg-relative.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/bg-relative-to-root.png')
      path = File.expand_path('../../client/testdata/images/bg-relative-to-root.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/bg-stacked.png')
      path = File.expand_path('../../client/testdata/images/bg-stacked.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/srcset-base.png')
      path = File.expand_path('../../client/testdata/images/srcset-base.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/srcset-first.png')
      path = File.expand_path('../../client/testdata/images/srcset-first.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource = find_resource(resources, '/images/srcset-second.png')
      path = File.expand_path('../../client/testdata/images/srcset-second.png', __FILE__)
      content = File.read(path)
      expect(resource.mimetype).to eq('image/png')
      expected_sha = Digest::SHA256.hexdigest(content)
      expect(Digest::SHA256.hexdigest(resource.content)).to eq(expected_sha)
      expect(resource.sha).to eq(expected_sha)

      resource_urls = resources.collect(&:resource_url).map do |url|
        url.gsub(/localhost:\d+/, 'localhost')
      end
      expect(resource_urls).to match_array([
        "http://localhost/images/img-relative.png",
        "http://localhost/images/img-relative-to-root.png",
        "http://localhost/images/percy.svg",
        "http://localhost/images/srcset-base.png",
        "http://localhost/images/srcset-first.png",
        "http://localhost/images/srcset-second.png",
        "http://localhost/images/bg-relative.png",
        "http://localhost/images/bg-relative-to-root.png",
        "http://localhost/images/bg-stacked.png"
      ])
      expect(resources.collect(&:is_root).uniq).to match_array([nil])
    end
  end
end
