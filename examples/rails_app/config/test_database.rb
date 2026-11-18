raise "Bundler is using a lockfile outside the worker" unless Bundler.default_lockfile.realpath == Rails.root.join("Gemfile.lock").realpath

ActiveRecord::Base.connection.create_table(:offers) do |table|
  table.integer :price_cents, null: false
  table.integer :stock, null: false
end

paths = [ActiveStorage::Engine, ActionMailbox::Engine].map { |engine| engine.root.join("db/migrate").to_s }
ActiveRecord::MigrationContext.new(paths).migrate
