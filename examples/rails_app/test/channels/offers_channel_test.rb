require "test_helper"

class OffersChannelTest < ActionCable::Channel::TestCase
  def test_subscription
    subscribe
    assert_has_stream "offers"
  end
end
