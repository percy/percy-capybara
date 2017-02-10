RSpec.describe Percy::Capybara::HttpFetcher do
  it 'takes a URL and returns a response' do
    response = Percy::Capybara::HttpFetcher.fetch('https://i.imgur.com/Umkjdao.png')

    # Slightly magical hash, just a SHA-256 sum of the image above.
    expect(Digest::SHA256.hexdigest(response.body)).to eq(
      '4beb51550bef8e9e30d37ea8c13658e99bb01722062f218185e419af5ad93e13',
    )
    expect(response.content_type).to eq('image/png')
  end
  it 'returns nil if fetch failed' do
    expect(Percy::Capybara::HttpFetcher.fetch('http://i.imgur.com/fake-image.png')).to be_nil
    expect(Percy::Capybara::HttpFetcher.fetch('http://i.imgur.com/fake image.png')).to be_nil
    # FIXME.
    # expect(Percy::Capybara::HttpFetcher.fetch('bad-url')).to be_nil
  end
end
