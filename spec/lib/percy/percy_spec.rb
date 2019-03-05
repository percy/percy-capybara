RSpec.describe Percy, type: :feature do
  TEST_CASE_GLOB =  File.join(File.dirname(__FILE__), "./capybara/client/test_data/test-*.html")

  describe '#snapshot', type: :feature, js: true do
    context 'with live sites' do
      it 'snapshots simple HTTPS site' do
        visit 'https://example.com'
        Percy.snapshot(page)
      end
      it 'snapshots complex HTTPS site' do
        visit 'https://polaris.shopify.com/'
        Percy.snapshot(page)
      end
      it 'snapshots site with strict CSP' do
        visit 'https://buildkite.com/'
        Percy.snapshot(page)
      end
    end
    context 'with different options' do
      it 'can get a default name' do
        visit 'http://example.com'
        Percy.snapshot(page)
      end
      it 'uses query params and fragment for default name' do
        visit 'http://example.com/?with_query'
        Percy.snapshot(page)
        visit 'http://example.com/?with_query_params#and-fragment'
        Percy.snapshot(page)
      end
      it 'uses provided name' do
        visit 'http://example.com'
        Percy.snapshot(page, name: 'My very special snapshot 🌟')
      end
      it 'recognizes requested widths' do
        visit 'http://example.com'
        Percy.snapshot(page, { name: 'widths', widths: [768, 992, 1200] })
      end
      it 'recognizes minHeight' do
        visit 'http://example.com'
        Percy.snapshot(page, { name: 'minHeight', minHeight: 2000 })
      end
    end
  end

  describe '_keys_to_json' do
    it 'transforms keys from snake_case to JSON-style' do
      original = { enable_javascript: true, minimum_height: 2000 }
      transformed = Percy._keys_to_json(original)
      expect(transformed.has_key? 'enableJavascript')
      expect(transformed.has_key? 'minHeight')
      expect(transformed['enableJavascript']).to eq(original[:enable_javascript])
      expect(transformed['minHeight']).to eq(original[:minimum_height])
    end
  end
end
