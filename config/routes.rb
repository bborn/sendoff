Sendoff::Engine.routes.draw do
  root to: "dashboard#index"

  # MCP server
  post "/mcp", to: "mcp#handle"

  # Pipeline (kanban)
  get "pipeline", to: "pipeline#index", as: :pipeline
  patch "pipeline/:id/move", to: "pipeline#move", as: :move_pipeline_entry

  # Leads
  resources :leads, only: [ :index, :show ] do
    member do
      post :queue
      post :enrich
      post :skip
      post :unskip
    end
  end

  # Companies
  resources :companies, only: [ :index, :show ]

  # Drafts
  resources :drafts, only: [ :index, :edit ] do
    member do
      post :send_now
      post :schedule
      post :refine
      post :discard
    end
  end

  # Voice rules
  resources :voice_rules, only: [ :index, :create, :update, :destroy ] do
    member { patch :toggle }
  end
end
