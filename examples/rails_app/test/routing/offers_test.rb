require "test_helper"

class OfferRoutesTest < ActionDispatch::IntegrationTest
  def test_show_route
    assert_routing "/offers/42", controller: "offers", action: "show", id: "42"
  end
end
