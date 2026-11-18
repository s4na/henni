require_relative "../rails_helper"

RSpec.describe "Opening an offer" do
  it "opens the offer page" do
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    visit offer_path(offer)
    expect(page).to have_button("Check discount")
  end
end
