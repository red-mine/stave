Rails.application.routes.draw do
  # resources :stocks
  # resources :staves

  get   "/:area",         to: "stocks#index"
  get   "/stocks/:stock", to: "stocks#show"

  root  "stocks#index"
end
