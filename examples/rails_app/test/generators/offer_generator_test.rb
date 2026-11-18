require "test_helper"
require "generators/offer_generator"

class OfferGeneratorTest < Rails::Generators::TestCase
  tests OfferGenerator
  destination Rails.root.join("tmp/generator")
  setup :prepare_destination

  def test_generator
    run_generator ["summer"]
    assert_file "offers/summer.txt", "Summer"
  end
end
