class CreateStocksCoefsStavs < ActiveRecord::Migration[7.0]
  def change
    create_table :stocks_coefs_stavs do |t|
      t.string  :stock
      t.string  :area
      t.float   :loha
      t.float   :loha_anti
      t.float   :year
      t.float   :year_anti
      t.float   :price
      t.boolean :good
      t.string  :lohas
      t.string  :years
      t.integer :boll3
      t.integer :stav3
      t.integer :boll1
      t.integer :stav1
      t.date    :date
    end
  end
end
