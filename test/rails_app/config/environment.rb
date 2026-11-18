require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_dispatch/system_test_case"

module Shop
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 8.1
    config.eager_load = false
    config.secret_key_base = "rails-test-fixture-" * 8
    config.hosts.clear
  end
end

Rails.application.initialize!
