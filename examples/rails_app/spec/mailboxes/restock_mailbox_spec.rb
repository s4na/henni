require_relative "../rails_helper"

RSpec.describe RestockMailbox do
  it "restocks from an incoming email" do
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    message = process(from: "supplier@example.org", to: "restock@example.org", subject: offer.id.to_s)
    expect(message).to have_been_delivered
    expect(offer.reload.stock).to eq(3)
  end
end
