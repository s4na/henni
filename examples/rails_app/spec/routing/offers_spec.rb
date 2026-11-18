require_relative "../rails_helper"

RSpec.describe "Offer routes" do
  it "routes an offer ID" do
    expect(get: "/offers/42").to route_to(controller: "offers", action: "show", id: "42")
  end
end
