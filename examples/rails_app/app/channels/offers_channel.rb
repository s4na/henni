class OffersChannel < ActionCable::Channel::Base
  def subscribed
    stream_from "offers"
  end
end
