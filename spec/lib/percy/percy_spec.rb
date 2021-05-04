RSpec.describe PercyCapybara, type: :feature do
  describe '#snapshot', type: :feature, js: true do
    context 'with live sites' do
      it 'snapshots simple HTTPS site' do
        visit 'https://example.com'
        page.percy_snapshot('name')
      end
    end
  end
end
