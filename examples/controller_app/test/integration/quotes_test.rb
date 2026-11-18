require_relative "../../app"
require "rails/test_help"

class QuotesTest < ActionDispatch::IntegrationTest
  def test_accepts_maximum_quantity
    post "/quotes", params: { quantity: 50 }, as: :json
    assert_response :ok
    assert_equal({ "unit_price" => 80, "total" => 4000 }, response.parsed_body)
  end

  def test_accepts_minimum_quantity
    post "/quotes", params: { quantity: 1 }
    assert_response :ok
    assert_equal({ "unit_price" => 100, "total" => 100 }, response.parsed_body)
  end

  def test_rejects_missing_or_invalid_quantity
    [{}, { quantity: "abc" }, { quantity: "1.5" }, { quantity: 0 }, { quantity: -1 }].each do |input|
      post "/quotes", params: input, as: :json
      assert_response :bad_request
      assert_equal({ "error" => "Enter a positive integer" }, response.parsed_body)
    end
  end
end
