class CreateStockFundamentals < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_fundamentals do |t|
      t.string :area, null: false
      t.string :stock, null: false
      t.string :name
      t.date :report_date
      t.float :roe
      t.float :revenue_yoy
      t.float :profit_yoy
      t.float :pe
      t.float :pe_ttm
      t.float :pb
      t.float :price
      t.bigint :market_cap
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :stock_fundamentals, %i[area stock], unique: true
  end
end
