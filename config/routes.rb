Rails.application.routes.draw do
  get "/:area", to: "stocks#index",
                as: :stocks_by_area,
                constraints: { area: /sz|sh|bj/ }
  get "/stocks/:stock", to: "stocks#show", as: :stock_analysis

  root  "stocks#index"
end
