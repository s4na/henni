require_relative "../rails_helper"

RSpec.describe OffersController do
  it "serves the discount" do
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    get :show, params: { id: offer.id }, format: :json
    expect(response.parsed_body.fetch("discount")).to be(true)
  end
end
