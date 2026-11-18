require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"
require "action_mailer/railtie"
require "active_storage/engine"
require "action_mailbox/engine"
require "action_cable/engine"
require "action_dispatch/system_test_case"

module Shop
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 8.1
    config.eager_load = false
    config.secret_key_base = "rails-test-fixture-" * 8
    config.active_record.maintain_test_schema = false
    config.active_job.queue_adapter = :test
    config.active_storage.service = :test
    config.action_mailer.delivery_method = :test
    config.action_mailbox.incinerate = false
    config.hosts.clear
  end
end

Rails.application.initialize!
