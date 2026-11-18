require_relative "../rails_helper"

RSpec.describe "offers/show.html.erb" do
  it "renders the discount button" do
    assign(:offer, Offer.create!(price_cents: 1_000, stock: 2))
    render
    expect(rendered).to have_button("Check discount")
  end
end
