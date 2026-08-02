module Stock
  class PreviewHealth
    def initialize(model: StocksCoefsStav)
      @model = model
    end

    def call
      markets = AREAS.to_h do |area|
        scope = @model.where(area: area)
        latest_date = scope.maximum(:date)
        rows = latest_date ? scope.where(date: latest_date).count : 0
        [area, { ready: latest_date.present? && rows.positive?, date: latest_date, rows: rows }]
      end

      { ready: markets.values.all? { |market| market[:ready] }, markets: markets }
    end
  end
end
