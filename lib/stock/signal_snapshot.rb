module Stock
  class SignalSnapshot
    def self.capture!(area)
      market = StocksCoefsStav.where(area: area)
      signal_date = market.maximum(:date)
      return 0 unless signal_date

      now = Time.current
      rows = market.where(date: signal_date).map do |record|
        {
          stock: record.stock, area: record.area, signal_date: signal_date,
          price: record.price, long_trend: record.loha, year_trend: record.year,
          lohas_signal: record.lohas, year_signal: record.years,
          lohas_channel: record.boll3, lohas_stave: record.stav3,
          year_channel: record.boll1, year_stave: record.stav1,
          created_at: now, updated_at: now
        }
      end

      StockSignalSnapshot.upsert_all(rows, unique_by: :index_signal_snapshots_on_area_stock_date) if rows.any?
      rows.size
    end
  end
end
