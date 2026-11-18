require "test_helper"
require "minitest/spec"

describe "Custom pricing" do
  it "grants a discount above the boundary" do
    _(Offer.new(price_cents: 1_001, stock: 2).discount?).must_equal true
  end
end
