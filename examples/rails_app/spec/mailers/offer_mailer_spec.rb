require_relative "../rails_helper"

RSpec.describe OfferMailer do
  it "addresses the availability message" do
    message = OfferMailer.available("customer@example.org")
    expect(message.to).to eq(["customer@example.org"])
    expect(message.subject).to eq("In stock")
  end
end
