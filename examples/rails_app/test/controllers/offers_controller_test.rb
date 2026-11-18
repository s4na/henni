require "test_helper"

class OffersControllerTest < ActionController::TestCase
  def test_discount
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    get :show, params: { id: offer.id }, format: :json
    assert_equal true, response.parsed_body.fetch("discount")
  end
end
