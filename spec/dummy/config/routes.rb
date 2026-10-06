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

  root "products#index"
end
