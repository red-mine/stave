module Stock
  class SignalTimeline
    Entry = Data.define(:date, :price, :year_signal, :lohas_signal, :changed)

    def initialize(area, stock, limit: 10)
      @area = area
      @stock = stock
      @limit = limit
    end

    def call
      snapshots = StockSignalSnapshot
        .where(area: @area, stock: @stock)
        .order(signal_date: :desc)
        .limit(@limit)
        .to_a
        .reverse

      snapshots.each_with_index.map do |snapshot, index|
        previous = snapshots[index - 1] if index.positive?
        changed = previous.present? && signal_pair(previous) != signal_pair(snapshot)

        Entry.new(
          date: snapshot.signal_date,
          price: snapshot.price,
          year_signal: snapshot.year_signal,
          lohas_signal: snapshot.lohas_signal,
          changed: changed
        )
      end.reverse
    end

    private

    def signal_pair(snapshot)
      [snapshot.year_signal, snapshot.lohas_signal]
    end
  end
end
