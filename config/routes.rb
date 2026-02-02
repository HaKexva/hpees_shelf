Rails.application.routes.draw do
  # Redirect old /batches to /batch_years (for bookmarks)
  get "/batches", to: redirect("/batch_years")
  get "/batches/new", to: redirect("/batch_years/new")
  get "/batches/bulk_destroy", to: redirect("/batch_years")
  get "/batches/:id", to: redirect("/batch_years/%{id}")
  get "/batches/:id/edit", to: redirect("/batch_years/%{id}/edit")

  resources :batch_years do
    collection do
      delete :bulk_destroy
    end
  end
  resources :books do
    collection do
      get :import
      post :import
      delete :bulk_destroy
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :users

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "dashboard#index"
end
