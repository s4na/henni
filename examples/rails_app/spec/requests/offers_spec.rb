require_relative "../rails_helper"

RSpec.describe "Offer pricing", type: :request do
  it "returns a discount at the price threshold" do
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    get offer_path(offer, format: :json)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("discount")).to be(true)
  end
end
