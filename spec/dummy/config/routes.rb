# The catalogue drawn the way a host draws it today: at its own top level,
# where the engine's top-level controllers answer.
Rails.application.routes.draw do
  resources :products do
    collection do
      get :search
      get "lookup/:code", action: :lookup, as: :lookup
    end
  end

  resources :brands do
    collection do
      get :search
    end
  end

  # An app's own door on the catalogue (app/controllers/bar_products_controller.rb).
  scope "bar", as: "bar" do
    resources :products, controller: "bar_products" do
      get "lookup/:code", action: :lookup, as: :lookup, on: :collection
    end
  end

  root "products#index"
end
