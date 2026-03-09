Rails.application.routes.draw do
  # Redirect old /batches to /batch_years (for bookmarks)
  get "/batches", to: redirect("/batch_years")
  get "/batches/new", to: redirect("/batch_years/new")
  get "/batches/bulk_destroy", to: redirect("/batch_years")
  get "/batches/:id", to: redirect("/batch_years/%{id}")
  get "/batches/:id/edit", to: redirect("/batch_years/%{id}/edit")

  resources :batch_years do
    collection do
      post :auto_create
      post :reassign_grades
      get :relocation
      post :apply_relocation
      post :save_relocation_draft
      post :rollback_school_year
      delete :bulk_destroy
    end
  end
  resources :books do
    member do
      post :return_to_library
      post :borrow
      post :return_shelf
    end
    collection do
      get :import
      post :import
      post :borrow_by_isbn
      get :return_to_library_batch
      post :apply_return_to_library_batch
      delete :bulk_destroy
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :users do
    member do
      get :cancel_resignation, to: redirect("/users/%{id}")
      post :cancel_resignation
    end
    collection do
      get :import
      post :import
      delete :bulk_destroy
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "dashboard#index"
  get "loan_history", to: "dashboard#loan_history", as: :loan_history
  get "validate_isbn", to: "dashboard#validate_isbn", as: :validate_isbn
  post "process_isbn", to: "dashboard#process_isbn", as: :process_isbn
  post "confirm_borrow_return", to: "dashboard#confirm_borrow_return", as: :confirm_borrow_return
end
