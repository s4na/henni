Rails.application.routes.draw do
  resources :offers, only: :show
end
