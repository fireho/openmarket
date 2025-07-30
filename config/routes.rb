Openmarket::Engine.routes.draw do
  resources :products do
    collection do
      get :search
    end
  end

  root 'products#index'

  # Legacy drink routes for backward compatibility (optional)
  # get '/drinks', to: redirect('/products')
  # get '/drinks/new', to: redirect('/products/new?type=Drink')
  # get '/drinks/:id', to: redirect('/products/%{id}')
  # get '/drinks/:id/edit', to: redirect('/products/%{id}/edit')
end
