require 'percy/capybara'

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
    context 'with local sites' do
      it 'can get a default name' do
        visit '/'
        Percy.snapshot(page)
      end
      it 'uses provided name' do
        visit '/'
        Percy.snapshot(page, name: 'My very special snapshot 🌟')
      end
      it 'recognizes requested widths' do
        visit '/'
        Percy.snapshot(page, { name: 'widths', widths: [768, 992, 1200] })
      end
      it 'recognizes minHeight' do
        visit '/'
        Percy.snapshot(page, { name: 'minHeight', minHeight: 2000 })
      end
      it 'works with all of our test case pages' do
        Dir.glob(TEST_CASE_GLOB) do |fname|
          case_name = File.basename(fname)
          visit case_name
          Percy.snapshot(page, name: case_name)
        end
      end
    end
  end
end
