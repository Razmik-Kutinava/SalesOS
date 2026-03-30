Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "health/ollama", to: "ollama_health#show"

  root "lead_console#show"

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  resources :leads, only: %i[index show]
  post "leads/:id/voice", to: "voice_commands#create", as: :voice_lead
  post "leads/:id/fetch_url", to: "fetch_urls#create", as: :lead_fetch_url
  post "console/voice", to: "voice_commands#create_console", as: :voice_console

  post "knowledge/query", to: "knowledge_queries#create", as: :knowledge_query

  resources :knowledge_documents, only: %i[create destroy] do
    collection do
      post :text, action: :create_from_text
    end
  end

  resources :lead_imports, only: %i[create show edit update]

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
