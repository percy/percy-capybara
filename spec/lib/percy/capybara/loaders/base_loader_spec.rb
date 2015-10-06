RSpec.describe Percy::Capybara::Loaders::BaseLoader do
  let(:loader) { described_class.new }

  describe '#root_html_resource', type: :feature, js: true do
    it 'includes the root DOM HTML' do
      visit '/'

      loader = described_class.new(page: page)
      resource = loader.root_html_resource

      expect(resource.is_root).to be_truthy
      expect(resource.mimetype).to eq('text/html')
      expect(resource.resource_url).to match('/')
      expect(resource.content).to include('Hello World!')
      expect(resource.sha).to eq(Digest::SHA256.hexdigest(resource.content))
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
      loader = described_class.new(page: page_double)
      expect(loader.current_path).to eq('/')

      expect(page_double).to receive(:current_url).and_return('/test')
      loader = described_class.new(page: page_double)
      expect(loader.current_path).to eq('/test')

      expect(page_double).to receive(:current_url).and_return('/test/a')
      loader = described_class.new(page: page_double)
      expect(loader.current_path).to eq('/test/a')

      # Rack::Test returns a full example.com URL, so we want to make sure it is stripped:
      expect(page_double).to receive(:current_url).and_return('http://www.example.com/')
      loader = described_class.new(page: page_double)
      expect(loader.current_path).to eq('/')

      expect(page_double).to receive(:current_url).and_return('about:srcdoc')
      loader = described_class.new(page: page_double)
      expect(loader.current_path).to eq('/about:srcdoc')
    end
  end
end


