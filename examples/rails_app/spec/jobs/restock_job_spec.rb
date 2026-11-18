require_relative "../rails_helper"

RSpec.describe RestockJob do
  it "restocks the persisted offer" do
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    perform_enqueued_jobs { RestockJob.perform_later(offer.id) }
    expect(offer.reload.stock).to eq(3)
  end
end
