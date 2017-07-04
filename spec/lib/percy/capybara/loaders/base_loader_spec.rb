IFRAME_PATH = File.expand_path('../../client/test_data/test-iframe.html', __FILE__)

class RackAppWithIframe
  def self.call(_env)
    [200, {}, File.read(IFRAME_PATH)]
  end
end

RSpec.describe Percy::Capybara::Loaders::BaseLoader do
  let(:loader) { Percy::Capybara::Loaders::BaseLoader.new }

  describe '#root_html_resource', type: :feature, js: true do
    it 'includes the root DOM HTML' do
      visit '/'

      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page)
      resource = loader.root_html_resource

      expect(resource.is_root).to be_truthy
      expect(resource.mimetype).to eq('text/html')
      expect(resource.resource_url).to match('/')
      expect(resource.content).to include('Hello World!')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))
    end
  end
  describe '#iframes_resources', type: :feature, js: true do
    it 'excludes the iframe by default' do
      visit '/test-iframe.html'

      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page)
      resources = loader.iframes_resources
      expect(resources).to eq([])
    end

    it 'includes the iframe with DOM HTML when include_iframes true' do
      visit '/test-iframe.html'

      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page, include_iframes: true)
      resources = loader.iframes_resources

      expect(resources.size).to eq(1) # doesn't include iframe to remote host
      last_resource = resources.last
      expect(last_resource.resource_url).to eq('/iframe.html')
      expect(last_resource.mimetype).to eq('text/html')
      expect(last_resource.content).to include('Inside iframe')
    end
    it 'skips poltergeist frame not found errors when include_iframes true' do
      visit '/test-iframe.html'

      expect(page).to receive(:within_frame).twice
        .and_raise(Capybara::Poltergeist::FrameNotFound, 'Hi')
      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page, include_iframes: true)
      resources = loader.iframes_resources
      expect(resources.size).to eq(0)
    end
    it 'skips poltergeist timeout errors when include_iframes true' do
      visit '/test-iframe.html'

      expect(page).to receive(:within_frame).twice
        .and_raise(Capybara::Poltergeist::TimeoutError, 'Hi')
      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page, include_iframes: true)
      resources = loader.iframes_resources
      expect(resources.size).to eq(0)
    end
  end
  describe '#build_resources' do
    it 'raises a NotImplementedError' do
      expect { loader.build_resources }.to raise_error(NotImplementedError)
    end
  end
  describe '#snapshot_resources' do
    it 'raises a NotImplementedError' do
      expect { loader.snapshot_resources }.to raise_error(NotImplementedError)
    end
  end
  describe '#current_path' do
    it 'returns the current path of the page, stripping the domain if it exists' do
      page_double = double('page')

      expect(page_double).to receive(:current_url).and_return('/')
      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page_double)
      expect(loader.current_path).to eq('/')

      expect(page_double).to receive(:current_url).and_return('/test')
      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page_double)
      expect(loader.current_path).to eq('/test')

      expect(page_double).to receive(:current_url).and_return('/test/a')
      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page_double)
      expect(loader.current_path).to eq('/test/a')

      # Rack::Test returns a full example.com URL, so we want to make sure it is stripped:
      expect(page_double).to receive(:current_url).and_return('http://www.example.com/')
      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page_double)
      expect(loader.current_path).to eq('/')

      expect(page_double).to receive(:current_url).and_return('about:srcdoc')
      loader = Percy::Capybara::Loaders::BaseLoader.new(page: page_double)
      expect(loader.current_path).to eq('/about:srcdoc')
    end
  end

  context 'Rack::Test', type: :feature do
    before(:each) { Capybara.app = RackAppWithIframe }
    after(:each) { Capybara.app = nil }

    describe '#iframes_resources' do
      it 'is silently ignored' do
        visit '/test-iframe.html'
        loader = Percy::Capybara::Loaders::BaseLoader.new(page: page)
        expect(loader.iframes_resources).to eq([])
      end
    end
  end

  describe '#_uri_join' do
    it 'joins files into a uri' do
      expect(Percy::Capybara::Loaders::BaseLoader.new.send(:_uri_join, 'foo/', '/bar', 'baz'))
        .to eq('foo/bar/baz')
    end
  end
end
