class CreateStockSignalSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_signal_snapshots do |t|
      t.string :stock, null: false
      t.string :area, null: false
      t.date :signal_date, null: false
      t.float :price
      t.float :long_trend
      t.float :year_trend
      t.string :lohas_signal
      t.string :year_signal
      t.integer :lohas_channel
      t.integer :lohas_stave
      t.integer :year_channel
      t.integer :year_stave
      t.timestamps
    end

    add_index :stock_signal_snapshots, [:area, :stock, :signal_date], unique: true,
      name: "index_signal_snapshots_on_area_stock_date"
    add_index :stock_signal_snapshots, [:area, :signal_date]
  end
end
