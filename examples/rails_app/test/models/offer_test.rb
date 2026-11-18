require "test_helper"

class OfferTest < ActiveSupport::TestCase
  def test_boundary
    assert_predicate Offer.new(price_cents: 1_000, stock: 2), :discount?
  end
end
