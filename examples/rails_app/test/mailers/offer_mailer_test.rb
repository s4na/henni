require "test_helper"

class OfferMailerTest < ActionMailer::TestCase
  def test_availability
    assert_emails 1 do
      OfferMailer.available("customer@example.org").deliver_now
    end
    assert_equal ["customer@example.org"], ActionMailer::Base.deliveries.last.to
  end
end
