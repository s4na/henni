require_relative "../rails_helper"

RSpec.describe "Checking a discount", type: :system do
  before do
    driven_by(:selenium, using: :headless_chrome) do |options|
      options.add_argument("--no-sandbox") if ENV["CI"]
    end
  end

  it "shows the discount returned by Rails when the shopper clicks" do
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    visit offer_path(offer)
    click_button "Check discount"
    expect(page).to have_css("output", text: "Discount available")
  end
end
