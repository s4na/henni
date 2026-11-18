ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rspec/rails"

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  config.before(:suite) do
    raise "Bundler is using a lockfile outside the worker" unless Bundler.default_lockfile.realpath == Rails.root.join("Gemfile.lock").realpath

    # Each worker must get its own empty SQLite database.
    ActiveRecord::Base.connection.create_table(:offers) do |table|
      table.integer :price_cents, null: false
      table.integer :stock, null: false
    end
  end
end
