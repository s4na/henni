module OffersHelper
  def price_label(cents)
    format("$%.2f", cents / 100.0)
  end
end
