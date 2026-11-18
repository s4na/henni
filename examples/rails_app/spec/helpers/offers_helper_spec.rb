require_relative "../rails_helper"

RSpec.describe OffersHelper do
  it "formats a price" do
    expect(helper.price_label(1_234)).to eq("$12.34")
  end
end
