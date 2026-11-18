require_relative "../rails_helper"

RSpec.describe OffersChannel do
  it "subscribes to offers" do
    subscribe
    expect(subscription).to have_stream_from("offers")
  end
end
