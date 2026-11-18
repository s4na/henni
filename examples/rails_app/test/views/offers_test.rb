require "test_helper"

class OfferViewTest < ActionView::TestCase
  def test_discount_button
    @offer = Offer.create!(price_cents: 1_000, stock: 2)
    render template: "offers/show"
    assert_select "button", "Check discount"
  end
end
