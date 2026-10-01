class DropUnusedLegacyTables < ActiveRecord::Migration[8.1]
  # Three tables were created early on and never used: no model, no query, no
  # rake task and no script references them, and DataStatus only inspects the
  # seven live coefficient/series tables. Dropping them keeps db/schema.rb an
  # accurate description of what the app actually stores.
  LEGACY_TABLES = %i[stave_staves staves stocks].freeze

  def up
    LEGACY_TABLES.each { |table| drop_table table }
  end

  # Reversible so a rollback restores the tables with their original columns.
  def down
    create_table :stave_staves do |t|
      t.string :area
      t.date :date
      t.float :price
      t.string :stock
      t.integer :years
    end

    create_table :staves do |t|
      t.date :date
      t.float :price
      t.string :stock
      t.integer :years
    end

    create_table :stocks do |t|
      t.string :area
      t.date :date
      t.float :price
      t.string :stock
    end
  end
end
