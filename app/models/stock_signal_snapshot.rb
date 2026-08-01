class StockSignalSnapshot < ApplicationRecord
  validates :stock, :area, :signal_date, presence: true
end
