class Offer < ActiveRecord::Base
  def discount?
    price_cents >= 1_000 && stock > 0
  end
end
