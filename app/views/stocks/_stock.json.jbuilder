json.extract! stock, :stock, :area, :loha, :year, :price, :boll1, :stav1, :boll3, :stav3, :years, :lohas, :date
json.url stock_analysis_url(stock.stock, area: stock.area, format: :json)
