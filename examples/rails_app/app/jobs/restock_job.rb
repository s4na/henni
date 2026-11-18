class RestockJob < ActiveJob::Base
  def perform(id)
    Offer.find(id).increment!(:stock)
  end
end
