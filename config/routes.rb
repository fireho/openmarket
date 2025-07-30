Openmarket::Engine.routes.draw do
  resources :items do
    collection do
      get :search
    end
  end

  root 'items#index'

  # Legacy drink routes for backward compatibility (optional)
  # get '/drinks', to: redirect('/items')
  # get '/drinks/new', to: redirect('/items/new?type=Drink')
  # get '/drinks/:id', to: redirect('/items/%{id}')
  # get '/drinks/:id/edit', to: redirect('/items/%{id}/edit')
end
