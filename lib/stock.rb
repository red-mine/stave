require_relative "stock/version"
require_relative "stock/railtie"
require_relative "stock/core_ext"
require_relative "stock/stave"
require_relative "stock/stock"

module Stock
  SZSTK = "sz"
  SHSTK = "sh"
  BJSTK = "bj"
  WEEKS = 5
  YEARS = 250
  STAVE = 20  * WEEKS
  LOHAS = 3   * YEARS + YEARS / 2
  SMUTH = 2   * WEEKS
end
