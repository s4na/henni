require "test_helper"

class RestockMailboxTest < ActionMailbox::TestCase
  def test_restock
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    message = receive_inbound_email_from_mail(from: "supplier@example.org", to: "restock@example.org", subject: offer.id.to_s)
    assert_predicate message.reload, :delivered?
    assert_equal 3, offer.reload.stock
  end
end
