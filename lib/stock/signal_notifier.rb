module Stock
  # Compares the two most recent signal snapshot dates for a market and
  # reports stocks whose signal family changed between them. Stocks that only
  # exist in the newer date (newly listed or newly calculated) are reported
  # with a nil previous_family.
  class SignalNotifier
    Event = Data.define(:stock, :family, :previous_family, :price, :year_signal, :lohas_signal)
    Report = Data.define(:area, :signal_date, :previous_date, :events) do
      def buys = events.select { |event| event.family == "buy" }

      def sells = events.select { |event| event.family == "sell" }

      def empty? = events.empty?
    end

    FAMILY_ORDER = { "buy" => 0, "sell" => 1, "watch" => 2 }.freeze

    def initialize(area)
      @area = area
    end

    def call
      dates = StockSignalSnapshot.where(area: @area).distinct.order(signal_date: :desc).limit(2).pluck(:signal_date)
      return Report.new(area: @area, signal_date: nil, previous_date: nil, events: []) if dates.size < 2

      signal_date, previous_date = dates
      current = snapshots_for(signal_date)
      previous = snapshots_for(previous_date)

      events = current.filter_map do |stock, snapshot|
        family = SignalFamily.classify(snapshot.year_signal, snapshot.lohas_signal)
        prior = previous[stock]
        previous_family = prior ? SignalFamily.classify(prior.year_signal, prior.lohas_signal) : nil
        next if family == previous_family

        Event.new(
          stock: stock, family: family, previous_family: previous_family, price: snapshot.price,
          year_signal: snapshot.year_signal, lohas_signal: snapshot.lohas_signal
        )
      end

      events.sort_by! { |event| [FAMILY_ORDER.fetch(event.family, 3), event.stock] }
      Report.new(area: @area, signal_date: signal_date, previous_date: previous_date, events: events)
    end

    private

    def snapshots_for(date)
      StockSignalSnapshot.where(area: @area, signal_date: date).index_by(&:stock)
    end
  end
end
