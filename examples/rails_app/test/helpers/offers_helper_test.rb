require "test_helper"

class OffersHelperTest < ActionView::TestCase
  def test_price_label
    assert_equal "$12.34", price_label(1_234)
  end
end
