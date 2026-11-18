require "test_helper"

class RestockJobTest < ActiveJob::TestCase
  def test_restock
    offer = Offer.create!(price_cents: 1_000, stock: 2)
    perform_enqueued_jobs { RestockJob.perform_later(offer.id) }
    assert_equal 3, offer.reload.stock
  end
end
