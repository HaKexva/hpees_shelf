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
      post :rollback_school_year
      delete :bulk_destroy
    end
  end
  resources :books do
    member do
      get :circulation_history
      post :return_to_library
      post :borrow
      post :return_shelf
    end
    collection do
      get :import
      post :import
      get :export
      get :inventory_pdf
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
      get :export
      delete :bulk_destroy
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "public_borrow_return#index"
  get "admin", to: "dashboard#index", as: :admin_dashboard
  get "loan_history", to: "dashboard#loan_history", as: :loan_history
  get "validate_isbn", to: "dashboard#validate_isbn", as: :validate_isbn
  post "process_isbn", to: "dashboard#process_isbn", as: :process_isbn
  get "public/validate_isbn", to: "public_borrow_return#validate_isbn", as: :public_validate_isbn
  post "public/process_isbn", to: "public_borrow_return#process_isbn", as: :public_process_isbn
  get "login", to: "sessions#new", as: :login
  get "google_auth_callback", to: "sessions#create", as: :google_auth_callback
  delete "logout", to: "sessions#destroy", as: :logout

  post "current_batch_year", to: "current_batch_years#update", as: :current_batch_year

  get "demo_login", to: "demo_sessions#new", as: :demo_login
  post "demo_login", to: "demo_sessions#create"
  get "demo_enter", to: "demo_sessions#enter", as: :demo_enter
  delete "demo_logout", to: "demo_sessions#destroy", as: :demo_logout
end
