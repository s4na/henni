require "action_controller/railtie"

class QuoteApp < Rails::Application
  config.root = __dir__
  config.load_defaults 8.1
  config.eager_load = false
  config.secret_key_base = "controller-fixture-" * 8
  config.hosts = ["example.org", "www.example.com"]
  config.action_controller.allow_forgery_protection = false
  config.action_dispatch.show_exceptions = :rescuable
  config.consider_all_requests_local = false
end

class QuotesController < ActionController::Base
  def create
    quantity = Integer(params[:quantity].to_s, 10, exception: false)
    unless quantity&.positive?
      return render json: { error: "Enter a positive integer" }, status: 400
    end
    if quantity > 50
      return render json: { error: "Maximum quantity is 50" }, status: 422
    end

    unit_price = quantity >= 10 ? 80 : 100
    render json: { unit_price: unit_price, total: unit_price * quantity }
  end
end

QuoteApp.initialize!
Rails.application.routes.draw do
  post "/quotes", to: "quotes#create"
end
