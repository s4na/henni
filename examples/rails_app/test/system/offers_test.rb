require "test_helper"

class OfferSystemTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome

  def test_discount
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    visit offer_path(offer)
    click_button "Check discount"
    assert_selector "output", text: "Discount available"
  end
end
