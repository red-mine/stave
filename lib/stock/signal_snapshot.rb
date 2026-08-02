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
        }
      end

      existing = StockSignalSnapshot.where(area: area, signal_date: signal_date).index_by(&:stock)
      to_insert = rows.reject { |row| existing.key?(row[:stock]) }
      to_update = rows.filter_map do |row|
        current = existing[row[:stock]]
        next unless current

        attributes = row.except(:stock, :area, :signal_date)
        next if attributes.all? { |key, value| current.public_send(key) == value }

        [current.id, attributes]
      end

      StockSignalSnapshot.insert_all(to_insert.map { |row| row.merge(created_at: now, updated_at: now) }) if to_insert.any?
      to_update.each do |id, attributes|
        StockSignalSnapshot.where(id: id).update_all(attributes.merge(updated_at: now))
      end
      rows.size
    end
  end
end
