RSpec.describe Percy::Capybara do
  before(:each) { Percy::Capybara.reset }

  describe '#capybara_client' do
    it 'returns the current client or creates a new one' do
      capybara_client = Percy::Capybara.capybara_client
      expect(capybara_client).to be
      # Verify that it memoizes the current object by calling it again:
      expect(Percy::Capybara.capybara_client).to eq(capybara_client)
    end
  end
  describe '#snapshot' do
    it 'passes all arguments through to the current capybara_client' do
      mock_page = double('page')
      capybara_client = Percy::Capybara.capybara_client
      expect(capybara_client).to receive(:snapshot).with(mock_page, {}).once
      Percy::Capybara.snapshot(mock_page)
      expect(capybara_client).to receive(:snapshot).with(mock_page, name: '/foo.html (modal)').once
      Percy::Capybara.snapshot(mock_page, name: '/foo.html (modal)')
    end
  end
  describe '#snapshot' do
    it 'delgates to Percy::Capybara::Client' do
      capybara_client = Percy::Capybara.capybara_client
      expect(capybara_client).to receive(:initialize_build).once
      Percy::Capybara.initialize_build
    end
  end
  describe '#finalize_build' do
    it 'returns silently if no build is initialized' do
      expect { Percy::Capybara.finalize_build }.to_not raise_error
    end
    it 'delgates to Percy::Capybara::Client' do
      capybara_client = Percy::Capybara.capybara_client
      build_data = {'data' => {'id' => 123}}
      expect(capybara_client.client).to receive(:create_build).and_return(build_data).once
      Percy::Capybara.initialize_build
      expect(capybara_client).to receive(:finalize_current_build).once
      Percy::Capybara.finalize_build
    end
  end
  describe '#reset' do
    it 'clears the current capybara_client' do
      capybara_client = Percy::Capybara.capybara_client
      Percy::Capybara.reset
      expect(Percy::Capybara.capybara_client).to_not eq(capybara_client)
    end
  end
end
