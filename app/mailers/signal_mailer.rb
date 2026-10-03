class SignalMailer < ApplicationMailer
  helper_method :stock_url_for

  def daily_digest(report)
    @report = report
    @base_url = ENV["STAVE_HOST"].to_s.sub(%r{/+\z}, "").presence
    @families = %w[buy sell watch].index_with { |family| report.events.select { |event| event.family == family } }

    subject = +"Stock Stave #{report.area.upcase} signal changes"
    subject << " #{report.signal_date}: #{report.buys.size} buy, #{report.sells.size} sell" if report.signal_date

    mail(
      to: ENV["STAVE_NOTIFY_EMAIL"].presence || "stave@localhost",
      from: ENV["STAVE_SMTP_FROM"].presence || ENV["STAVE_SMTP_USER"].presence || "stave@localhost",
      subject: subject
    )
  end

  private

  def stock_url_for(stock)
    "#{@base_url}/stocks/#{stock}" if @base_url
  end
end
