class StockFundamental < ApplicationRecord
  validates :stock, :area, presence: true
end
