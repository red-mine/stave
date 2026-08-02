json.stock @stock
json.area @area
json.data_date @stock_date
json.market_date @market_date
json.historical @historical_data
json.decision @current_decision
json.latest_signal do
  if @signal_timeline.any?
    current = @signal_timeline.first
    json.date current.date
    json.price current.price
    json.year_signal current.year_signal
    json.lohas_signal current.lohas_signal
  else
    json.nil!
  end
end
json.signal_history @signal_timeline do |entry|
  json.date entry.date
  json.price entry.price
  json.year_signal entry.year_signal
  json.lohas_signal entry.lohas_signal
  json.changed entry.changed
end
json.charts do
  json.stave_lohas @stave_lohas
  json.stave_years @stave_years
  json.bolls_lohas @bolls_lohas
  json.bolls_years @bolls_years
end
