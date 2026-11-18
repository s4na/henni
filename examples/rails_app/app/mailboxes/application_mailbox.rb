class ApplicationMailbox < ActionMailbox::Base
  routing "restock@example.org" => :restock
end
