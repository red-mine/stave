require_relative "stock/version"
require_relative "stock/railtie"
require_relative "stock/core_ext"
require_relative "stock/data_status"
require_relative "stock/stave"
require_relative "stock/stock"
require "pathname"

module Stock
  SZSTK = "sz"
  SHSTK = "sh"
  BJSTK = "bj"
  WEEKS = 5
  YEARS = 250
  STAVE = 20  * WEEKS
  LOHAS = 3   * YEARS + YEARS / 2
  SMUTH = 2   * WEEKS

  def self.data_root
    default_root = if RUBY_PLATFORM == "x86_64-linux-gnu"
      "vipdoc"
    else
      "C:/new_tdx/vipdoc"
    end
    Pathname.new(ENV.fetch("TDX_DATA_PATH", default_root)).expand_path
  end
end
