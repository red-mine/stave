Rails.application.routes.draw do
  get "/signal-guide", to: "stocks#signal_guide", as: :signal_guide
  get "/:area", to: "stocks#index",
                as: :stocks_by_area,
                constraints: { area: /sz|sh|bj/ }
  get "/stocks/:stock", to: "stocks#show", as: :stock_analysis

  root  "stocks#index"
end
