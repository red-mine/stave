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

ActiveRecord::Schema[7.0].define(version: 2026_08_01_000000) do
  create_table "stave_staves", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "price"
    t.date "date"
    t.integer "years"
  end

  create_table "staves", force: :cascade do |t|
    t.string "stock"
    t.float "price"
    t.date "date"
    t.integer "years"
  end

  create_table "stocks", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "price"
    t.date "date"
  end

  create_table "stocks_bolls_lohas", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "price"
    t.date "date"
    t.string "years"
    t.index ["area", "stock", "years", "date"], name: "index_stocks_bolls_lohas_on_area_and_stock_and_years_and_date", unique: true
  end

  create_table "stocks_bolls_years", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "price"
    t.date "date"
    t.string "years"
    t.index ["area", "stock", "years", "date"], name: "index_stocks_bolls_years_on_area_and_stock_and_years_and_date", unique: true
  end

  create_table "stocks_coefs_lohas", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "coef"
    t.float "inter"
    t.float "price"
    t.boolean "good"
    t.string "stave"
    t.integer "boll"
    t.integer "stav"
    t.date "date"
    t.integer "years"
    t.index ["area", "stock"], name: "index_stocks_coefs_lohas_on_area_and_stock", unique: true
  end

  create_table "stocks_coefs_stavs", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "loha"
    t.float "year"
    t.float "price"
    t.boolean "good"
    t.string "lohas"
    t.string "years"
    t.integer "boll3"
    t.integer "stav3"
    t.integer "boll1"
    t.integer "stav1"
    t.date "date"
    t.index ["area", "price"], name: "index_stocks_coefs_stavs_on_area_and_price"
    t.index ["area", "stock"], name: "index_stocks_coefs_stavs_on_area_and_stock", unique: true
  end

  create_table "stocks_coefs_years", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "coef"
    t.float "inter"
    t.float "price"
    t.boolean "good"
    t.string "stave"
    t.integer "boll"
    t.integer "stav"
    t.date "date"
    t.integer "years"
    t.index ["area", "stock"], name: "index_stocks_coefs_years_on_area_and_stock", unique: true
  end

  create_table "stocks_stave_lohas", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "price"
    t.date "date"
    t.string "years"
    t.index ["area", "stock", "years", "date"], name: "index_stocks_stave_lohas_on_area_and_stock_and_years_and_date", unique: true
  end

  create_table "stocks_stave_years", force: :cascade do |t|
    t.string "stock"
    t.string "area"
    t.float "price"
    t.date "date"
    t.string "years"
    t.index ["area", "stock", "years", "date"], name: "index_stocks_stave_years_on_area_and_stock_and_years_and_date", unique: true
  end

end
