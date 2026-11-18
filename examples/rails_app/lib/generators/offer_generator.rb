require "rails/generators"

class OfferGenerator < Rails::Generators::NamedBase
  def create_offer
    create_file "offers/#{file_name}.txt", human_name
  end
end
