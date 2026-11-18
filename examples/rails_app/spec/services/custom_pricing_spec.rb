require_relative "../rails_helper"

RSpec.describe "Custom pricing" do
  it "discovers application-specific spec directories" do
    expect(Offer.new(price_cents: 1_001, stock: 2).discount?).to be(true)
  end
end
