require "test_helper"

class SignalMailerTest < ActionMailer::TestCase
  setup do
    @report = Stock::SignalNotifier::Report.new(
      area: Stock::SZSTK,
      signal_date: Date.new(2026, 7, 31),
      previous_date: Date.new(2026, 7, 30),
      events: [
        Stock::SignalNotifier::Event.new(
          stock: "sz000001", family: "buy", previous_family: "watch", price: 12.5,
          year_signal: "SAF1", lohas_signal: "BUY5"
        )
      ]
    )
  end

  test "digest lists grouped events and links stocks when STAVE_HOST is set" do
    with_env "STAVE_NOTIFY_EMAIL" => "investor@example.com", "STAVE_HOST" => "https://stave.example.com" do
      mail = SignalMailer.daily_digest(@report)

      assert_equal ["investor@example.com"], mail.to
      assert_equal "Stock Stave SZ signal changes 2026-07-31: 1 buy, 0 sell", mail.subject
      assert_match %r{https://stave\.example\.com/stocks/sz000001}, mail.html_part.body.decoded
      assert_match %r{https://stave\.example\.com/stocks/sz000001}, mail.text_part.body.decoded
      assert_match "watch -> buy", mail.text_part.body.decoded
    end
  end

  test "digest renders without links when STAVE_HOST is not set" do
    with_env "STAVE_NOTIFY_EMAIL" => "investor@example.com", "STAVE_HOST" => nil do
      mail = SignalMailer.daily_digest(@report)

      assert_no_match %r{stocks/sz000001}, mail.text_part.body.decoded
      assert_match "sz000001", mail.text_part.body.decoded
    end
  end

  private

  def with_env(overrides)
    original = overrides.to_h { |key, _value| [key, ENV[key]] }
    overrides.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
