require_relative "../rails_helper"
require "generators/offer_generator"

RSpec.describe "Offer generator" do
  it "writes the named offer" do
    Dir.mktmpdir do |dir|
      OfferGenerator.start(["summer"], destination_root: dir)
      expect(File.read(File.join(dir, "offers/summer.txt"))).to eq("Summer")
    end
  end
end
