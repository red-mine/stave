require "test_helper"

class AnalysisIndexTest < ActiveSupport::TestCase
  COEFFICIENT_TABLES = %w[
    stocks_coefs_lohas
    stocks_coefs_years
    stocks_coefs_stavs
  ].freeze

  SERIES_TABLES = %w[
    stocks_stave_lohas
    stocks_stave_years
    stocks_bolls_lohas
    stocks_bolls_years
  ].freeze

  test "coefficient rows are unique per market and stock" do
    COEFFICIENT_TABLES.each do |table|
      index = unique_index_for(table, %w[area stock])

      assert index, "expected #{table} to have a unique market/stock index"
    end
  end

  test "chart rows are unique per market stock series and date" do
    SERIES_TABLES.each do |table|
      index = unique_index_for(table, %w[area stock years date])

      assert index, "expected #{table} to have a unique chart-series index"
    end
  end

  private

  def unique_index_for(table, columns)
    ActiveRecord::Base.connection.indexes(table).find do |index|
      index.unique && index.columns == columns
    end
  end
end
