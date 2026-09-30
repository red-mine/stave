class RenameCoefsStavSignalColumns < ActiveRecord::Migration[8.1]
  def change
    rename_column :stocks_coefs_stavs, :years, :year_signal
    rename_column :stocks_coefs_stavs, :lohas, :lohas_signal
  end
end
