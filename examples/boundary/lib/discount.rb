module Discount
  def self.eligible?(price)
    price >= 1_000
  end
end
