require "test_helper"
require "rake"

class DailyRefreshTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("daily_refresh")
    Rake::Task["daily_refresh"].reenable
  end

  teardown do
    Rake::Task["daily_refresh"].reenable
  end

  test "records snapshots for every market even when none need refreshing" do
    market = { healthy: true, source_date: Date.new(2026, 7, 31) }
    checker = Stock::DataStatus.allocate
    checker.stub(:call, Stock::AREAS.index_with { market }) do
      captured = []

      Stock::DataStatus.stub(:new, ->(*) { checker }) do
        Stock::SignalSnapshot.stub(:capture!, ->(area) { captured << area; 0 }) do
          Rake::Task["daily_refresh"].invoke
        end
      end

      assert_equal Stock::AREAS, captured
    end
  end

  test "refreshes stale markets before recording snapshots" do
    healthy_market = { healthy: true, source_date: Date.new(2026, 7, 31) }
    stale_market = { healthy: false, source_date: Date.new(2026, 7, 30) }
    checker = Stock::DataStatus.allocate
    call_count = 0

    checker.stub(:call, -> {
      call_count += 1
      if call_count == 1
        {
          Stock::SZSTK => healthy_market,
          Stock::SHSTK => stale_market,
          Stock::BJSTK => healthy_market
        }
      else
        Stock::AREAS.index_with { healthy_market }
      end
    }) do
      refreshed = []

      Stock::DataStatus.stub(:new, ->(*) { checker }) do
        Stock::SignalSnapshot.stub(:capture!, 0) do
          Rake::Task[:refresh].stub(:invoke, ->(*areas) { refreshed.concat(areas) }) do
            Rake::Task["daily_refresh"].invoke
          end
        end
      end

      assert_equal [Stock::SHSTK], refreshed
      assert_equal 2, call_count
    end
  end
end
