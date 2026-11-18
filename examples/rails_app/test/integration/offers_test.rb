require "test_helper"

class OfferRequestTest < ActionDispatch::IntegrationTest
  def test_discount
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    get offer_path(offer, format: :json)
    assert_response :success
    assert_equal true, response.parsed_body.fetch("discount")
  end
end
