Rails.application.routes.draw do
  # resources :stocks
  # resources :staves
  root  "stocks#index"
  get   "/stocks",          to: "stocks#index"
  get   "/:area",           to: "stocks#index"
  get   "/stocks/:stock",   to: "stocks#show"
end
