require_relative "../rails_helper"

RSpec.describe Offer do
  it "includes the threshold" do
    offer = Offer.new(price_cents: 1_000, stock: 1)
    expect(offer.discount?).to be(true)
  end
end
