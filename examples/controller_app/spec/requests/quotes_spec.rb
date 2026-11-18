require_relative "../../app"
require "rack/test"

RSpec.describe "POST /quotes" do
  include Rack::Test::Methods

  def app
    Rails.application
  end

  it "charges the regular price just below the discount" do
    post "/quotes", quantity: "9"
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq("unit_price" => 100, "total" => 900)
  end

  it "discounts a JSON order at the first eligible quantity" do
    post "/quotes", JSON.generate(quantity: 10), "CONTENT_TYPE" => "application/json"
    expect(last_response.status).to eq(200)
    expect(last_response.media_type).to eq("application/json")
    expect(JSON.parse(last_response.body)).to eq("unit_price" => 80, "total" => 800)
  end

  it "rejects a quantity above the maximum" do
    post "/quotes", quantity: "51"
    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body)).to eq("error" => "Maximum quantity is 50")
  end

  it "requires POST on the quote endpoint" do
    get "/quotes"
    expect(last_response.status).to eq(404)
  end

  it "returns a bad request for malformed JSON" do
    post "/quotes", "{", "CONTENT_TYPE" => "application/json"
    expect(last_response.status).to eq(400)
  end
end
