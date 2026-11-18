class RestockMailbox < ApplicationMailbox
  def process
    RestockJob.perform_now(Integer(mail.subject))
  end
end
