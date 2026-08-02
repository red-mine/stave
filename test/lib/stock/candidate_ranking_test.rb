require "test_helper"

class StockCandidateRankingTest < ActiveSupport::TestCase
  test "ranks explainable current A-share buy candidates and excludes index codes" do
    strong = create_candidate(
      stock: "sh603087", years: "BUY5", lohas: "BUY5",
      year: 0.04, loha: 0.03, boll1: 1, stav1: 1, boll3: 1, stav3: 1
    )
    create_candidate(stock: "sh600001", years: "SAF1", lohas: "BUY4", year: 0.01, loha: 0.01)
    create_candidate(stock: "sh880016", years: "BUY5", lohas: "BUY5", year: 0.1, loha: 0.1)
    create_candidate(stock: "sh600002", years: "BUY5", lohas: "BUY5", date: Date.new(2026, 7, 30))

    candidates = Stock::CandidateRanking.new(Stock::SHSTK).call

    assert_equal %w[sh603087 sh600001], candidates.map(&:stock)
    assert_equal 100, candidates.first.score
    assert_equal "Strong", candidates.first.confidence
    assert_equal strong, candidates.first.record
    assert_includes candidates.first.reasons, "Price position is supported on both horizons"
    assert_equal "First recorded", candidates.first.history_state
  end

  test "identifies new and continuing buys from prior recorded snapshots" do
    create_candidate(stock: "sz000001", years: "BUY5", lohas: "BUY5")
    create_candidate(stock: "sz000002", years: "BUY5", lohas: "BUY5")
    create_snapshot(stock: "sz000001", years: "WAT9", lohas: "WAT9")
    create_snapshot(stock: "sz000002", years: "SAF1", lohas: "BUY4")

    candidates = Stock::CandidateRanking.new(Stock::SZSTK).call

    assert_equal "New buy signal", candidates.find { |candidate| candidate.stock == "sz000001" }.history_state
    assert_equal "Still active", candidates.find { |candidate| candidate.stock == "sz000002" }.history_state
  end

  test "uses each candidate's latest prior observation" do
    create_candidate(stock: "sz000001", years: "BUY5", lohas: "BUY5")
    create_snapshot(stock: "sz000001", years: "WAT9", lohas: "WAT9", date: Date.new(2026, 7, 29))
    create_snapshot(stock: "sz000001", years: "SAF1", lohas: "BUY4", date: Date.new(2026, 7, 30))

    candidate = Stock::CandidateRanking.new(Stock::SZSTK).call.first

    assert_equal "Still active", candidate.history_state
  end

  test "limits the ranked result" do
    3.times { |index| create_candidate(stock: "sz00000#{index}", years: "BUY5", lohas: "BUY5") }

    assert_equal 2, Stock::CandidateRanking.new(Stock::SZSTK).call(limit: 2).size
  end

  private

  def create_candidate(stock:, years:, lohas:, date: Date.new(2026, 7, 31), **attributes)
    StocksCoefsStav.create!({
      stock:, area: stock.first(2), price: 50, date:, years:, lohas:,
      year: -0.01, loha: -0.01, boll1: -1, stav1: -1, boll3: -1, stav3: -1
    }.merge(attributes))
  end

  def create_snapshot(stock:, years:, lohas:, date: Date.new(2026, 7, 30))
    StockSignalSnapshot.create!(
      stock: stock, area: stock.first(2), signal_date: date,
      price: 49, year_signal: years, lohas_signal: lohas
    )
  end
end
