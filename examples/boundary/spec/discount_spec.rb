require_relative "../lib/discount"

RSpec.describe Discount do
  it "applies above the threshold" do
    expect(Discount.eligible?(1_001)).to be(true)
  end
end
