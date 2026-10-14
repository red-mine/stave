# Ground truth for the Python replay: run the real engine on historical days.
#
#   bin/rails runner research/event_study/engine_truth.rb SAMPLES.csv OUT.jsonl
#
# SAMPLES.csv rows are "area,stock,date,window" (date yyyymmdd, window
# lohas|year). For each row the engine is built with the trim that makes the
# file end on that date, so it sees exactly the data it would have seen then.
require "json"

samples_path, out_path = ARGV.fetch(0), ARGV.fetch(1)
years_for = { "lohas" => Stock::LOHAS, "year" => Stock::YEARS }

def trim_for(path, date)
  size = File.size(path) / 32
  File.open(path, "rb") do |file|
    (size - 1).downto(0) do |index|
      file.seek(index * 32)
      record_date = file.read(4).unpack1("L<")
      return size - 1 - index if record_date == date
      return nil if record_date < date
    end
  end
  nil
end

File.open(out_path, "w") do |out|
  File.foreach(samples_path).drop(1).each do |line|
    area, stock, date, window = line.chomp.split(",")
    path = File.join(Stock.data_root, area, "lday", "#{stock}.day")
    trim = trim_for(path, date.to_i)
    result = if trim
      engine = Stock::Stock.new(area, years_for.fetch(window), trim: trim)
      engine.signal_for(stock)
    end
    out.puts({
      area: area, stock: stock, date: date.to_i, window: window,
      found: !trim.nil?,
      valid: !result.nil?,
      signal: result&.dig(:stave) || "",
      stav: result&.dig(:stav) || 0,
      boll: result ? (result[:boll].is_a?(Integer) ? result[:boll] : 0) : 0,
      coef: result&.dig(:model, :coef)
    }.to_json)
  end
end
