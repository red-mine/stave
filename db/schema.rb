# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_01_010000) do
  create_table "stave_staves", force: :cascade do |t|
    t.string "area"
    t.date "date"
    t.float "price"
    t.string "stock"
    t.integer "years"
  end

  create_table "staves", force: :cascade do |t|
    t.date "date"
    t.float "price"
    t.string "stock"
    t.integer "years"
  end

  create_table "stock_signal_snapshots", force: :cascade do |t|
    t.string "area", null: false
    t.datetime "created_at", null: false
    t.integer "lohas_channel"
    t.string "lohas_signal"
    t.integer "lohas_stave"
    t.float "long_trend"
    t.float "price"
    t.date "signal_date", null: false
    t.string "stock", null: false
    t.datetime "updated_at", null: false
    t.integer "year_channel"
    t.string "year_signal"
    t.integer "year_stave"
    t.float "year_trend"
    t.index ["area", "signal_date"], name: "index_stock_signal_snapshots_on_area_and_signal_date"
    t.index ["area", "stock", "signal_date"], name: "index_signal_snapshots_on_area_stock_date", unique: true
  end

  create_table "stocks", force: :cascade do |t|
    t.string "area"
    t.date "date"
    t.float "price"
    t.string "stock"
  end

  create_table "stocks_bolls_lohas", force: :cascade do |t|
    t.string "area"
    t.date "date"
    t.float "price"
    t.string "stock"
    t.string "years"
    t.index ["area", "stock", "years", "date"], name: "index_stocks_bolls_lohas_on_area_and_stock_and_years_and_date", unique: true
  end

  create_table "stocks_bolls_years", force: :cascade do |t|
    t.string "area"
    t.date "date"
    t.float "price"
    t.string "stock"
    t.string "years"
    t.index ["area", "stock", "years", "date"], name: "index_stocks_bolls_years_on_area_and_stock_and_years_and_date", unique: true
  end

  create_table "stocks_coefs_lohas", force: :cascade do |t|
    t.string "area"
    t.integer "boll"
    t.float "coef"
    t.date "date"
    t.boolean "good"
    t.float "inter"
    t.float "price"
    t.integer "stav"
    t.string "stave"
    t.string "stock"
    t.integer "years"
    t.index ["area", "stock"], name: "index_stocks_coefs_lohas_on_area_and_stock", unique: true
  end

  create_table "stocks_coefs_stavs", force: :cascade do |t|
    t.string "area"
    t.integer "boll1"
    t.integer "boll3"
    t.date "date"
    t.boolean "good"
    t.float "loha"
    t.string "lohas"
    t.float "price"
    t.integer "stav1"
    t.integer "stav3"
    t.string "stock"
    t.float "year"
    t.string "years"
    t.index ["area", "price"], name: "index_stocks_coefs_stavs_on_area_and_price"
    t.index ["area", "stock"], name: "index_stocks_coefs_stavs_on_area_and_stock", unique: true
  end

  create_table "stocks_coefs_years", force: :cascade do |t|
    t.string "area"
    t.integer "boll"
    t.float "coef"
    t.date "date"
    t.boolean "good"
    t.float "inter"
    t.float "price"
    t.integer "stav"
    t.string "stave"
    t.string "stock"
    t.integer "years"
    t.index ["area", "stock"], name: "index_stocks_coefs_years_on_area_and_stock", unique: true
  end

  create_table "stocks_stave_lohas", force: :cascade do |t|
    t.string "area"
    t.date "date"
    t.float "price"
    t.string "stock"
    t.string "years"
    t.index ["area", "stock", "years", "date"], name: "index_stocks_stave_lohas_on_area_and_stock_and_years_and_date", unique: true
  end

  create_table "stocks_stave_years", force: :cascade do |t|
    t.string "area"
    t.date "date"
    t.float "price"
    t.string "stock"
    t.string "years"
    t.index ["area", "stock", "years", "date"], name: "index_stocks_stave_years_on_area_and_stock_and_years_and_date", unique: true
  end
end
