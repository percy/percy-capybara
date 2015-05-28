RSpec.describe Percy::Capybara::Client do
  it 'accepts and memoizes a client arg' do
    client = Percy::Client.new
    capybara_client = Percy::Capybara::Client.new(client: client)
    expect(capybara_client.client).to eq(client)
  end
  describe '#enabled?' do
    before(:each) { @original_env = ENV['TRAVIS_BUILD_ID'] }
    after(:each) do
      ENV['TRAVIS_BUILD_ID'] = @original_env
      ENV['PERCY_ENABLE'] = nil
    end

    context 'in supported CI environment' do
      it 'is true' do
        ENV['TRAVIS_BUILD_ID'] = '123'
        expect(Percy::Capybara::Client.new.enabled?).to be_truthy
      end
    end
    it 'is false by default for local dev environments or unknown CI environments' do
      expect(Percy::Capybara::Client.new.enabled?).to be_falsey
    end
    it 'is true if PERCY_ENABLE=1 is set' do
      ENV['PERCY_ENABLE'] = '1'
      expect(Percy::Capybara::Client.new.enabled?).to be_truthy
    end
  end
end

