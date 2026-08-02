module Stock
  class PreviewHealth
    def initialize(model: StocksCoefsStav, snapshot_model: StockSignalSnapshot)
      @model = model
      @snapshot_model = snapshot_model
    end

    def call
      markets = AREAS.to_h do |area|
        scope = @model.where(area: area)
        latest_date = scope.maximum(:date)
        rows = latest_date ? scope.where(date: latest_date).count : 0
        snapshots = @snapshot_model.where(area: area)
        snapshot_date = snapshots.maximum(:signal_date)
        snapshot_rows = snapshot_date ? snapshots.where(signal_date: snapshot_date).count : 0
        ready = latest_date.present? && rows.positive? && snapshot_date == latest_date && snapshot_rows == rows
        [area, {
          ready: ready, date: latest_date, rows: rows,
          snapshot_date: snapshot_date, snapshot_rows: snapshot_rows
        }]
      end

      dates = markets.values.filter_map { |market| market[:date] }.uniq
      dates_aligned = dates.one? && markets.values.all? { |market| market[:date] == dates.first }
      {
        ready: dates_aligned && markets.values.all? { |market| market[:ready] },
        date: dates_aligned ? dates.first : nil,
        dates_aligned: dates_aligned,
        markets: markets
      }
    end
  end
end
