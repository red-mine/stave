class AddAnalysisIndexes < ActiveRecord::Migration[7.0]
  COEFFICIENT_TABLES = %i[
    stocks_coefs_lohas
    stocks_coefs_years
    stocks_coefs_stavs
  ].freeze

  SERIES_TABLES = %i[
    stocks_stave_lohas
    stocks_stave_years
    stocks_bolls_lohas
    stocks_bolls_years
  ].freeze

  def change
    COEFFICIENT_TABLES.each do |table|
      add_index table, %i[area stock], unique: true
    end

    add_index :stocks_coefs_stavs, %i[area price]

    SERIES_TABLES.each do |table|
      add_index table, %i[area stock years date], unique: true
    end
  end
end
