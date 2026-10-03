module Stock
  # Runs the same LOHAS five-line + channel combination the stock pipeline
  # uses over curated broad-market indexes and ETFs. The stock pipeline skips
  # these instruments silently because its data guard rejects closes above
  # 100 yuan (Stock::STAVE), which every index point level violates; here the
  # guard is lifted via max_price: nil. The strategy's own slope precondition
  # is kept — an instrument without a positive regression trend reads as
  # :no_model instead of producing a signal, matching how the method treats
  # downtrending stocks.
  class IndexSignals
    # Broad, liquid benchmarks only; each entry needs a TongdaXin daily file
    # (area/lday/<code>.day) with at least LOHAS + STAVE records. BJ has no
    # index daily files, so it has no entries.
    INSTRUMENTS = [
      { code: "sh000001", area: SHSTK, name: "上证综指" },
      { code: "sh000016", area: SHSTK, name: "上证50" },
      { code: "sh000300", area: SHSTK, name: "沪深300" },
      { code: "sh000688", area: SHSTK, name: "科创50" },
      { code: "sh000905", area: SHSTK, name: "中证500" },
      { code: "sz399001", area: SZSTK, name: "深证成指" },
      { code: "sz399006", area: SZSTK, name: "创业板指" },
      { code: "sh510050", area: SHSTK, name: "上证50ETF" },
      { code: "sh510300", area: SHSTK, name: "沪深300ETF" },
      { code: "sh510500", area: SHSTK, name: "中证500ETF" },
      { code: "sh588000", area: SHSTK, name: "科创50ETF" },
      { code: "sz159915", area: SZSTK, name: "创业板ETF" }
    ].map(&:freeze).freeze

    # status: :ok          — both horizons computed
    #         :no_model    — data present, but the trend precondition fails
    #         :no_data     — daily file missing or shorter than LOHAS+STAVE
    Reading = Data.define(
      :code, :name, :area, :date, :price, :loha, :year,
      :lohas_signal, :year_signal, :lohas_stave, :family, :status
    )

    def initialize(area = nil)
      @area = area
    end

    def call
      instruments.filter_map { |instrument| reading(instrument) }
    end

    private

    def instruments
      return INSTRUMENTS unless @area

      INSTRUMENTS.select { |instrument| instrument[:area] == @area }
    end

    def reading(instrument)
      area = instrument[:area]
      code = instrument[:code]
      lohas_engine = Stock.new(area, LOHAS, max_price: nil)
      years_engine = Stock.new(area, YEARS, max_price: nil)

      lohas = lohas_engine.signal_for(code)
      status = lohas ? :ok : (sufficient_data?(area, code) ? :no_model : :no_data)
      return unfinished(instrument, status) unless status == :ok

      years = years_engine.signal_for(code)
      Reading.new(
        code: code,
        name: instrument[:name],
        area: area,
        date: lohas[:model][:date],
        price: lohas[:model][:price],
        loha: lohas[:model][:coef],
        year: years&.dig(:model, :coef),
        lohas_signal: lohas[:stave],
        year_signal: years&.dig(:stave),
        lohas_stave: lohas[:stav],
        family: SignalFamily.classify(years&.dig(:stave), lohas[:stave]),
        status: :ok
      )
    end

    def unfinished(instrument, status)
      Reading.new(
        code: instrument[:code],
        name: instrument[:name],
        area: instrument[:area],
        date: nil,
        price: nil,
        loha: nil,
        year: nil,
        lohas_signal: nil,
        year_signal: nil,
        lohas_stave: nil,
        family: nil,
        status: status
      )
    end

    def sufficient_data?(area, code)
      path = ::Stock.data_root.join(area, "lday", "#{code}.day")
      File.file?(path) && File.size(path) > (LOHAS + STAVE) * 32
    end
  end
end
