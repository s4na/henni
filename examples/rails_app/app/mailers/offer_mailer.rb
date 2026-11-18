class OfferMailer < ActionMailer::Base
  def available(address)
    mail(from: "shop@example.org", to: address, subject: "In stock", body: "Your offer is available.")
  end
end
