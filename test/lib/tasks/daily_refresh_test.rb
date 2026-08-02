require "test_helper"
require "rake"

class DailyRefreshTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("daily_refresh")
    Rake::Task["daily_refresh"].reenable
    @refresh_directory = Dir.mktmpdir("daily-refresh-test")
  end

  teardown do
    Rake::Task["daily_refresh"].reenable
    FileUtils.remove_entry(@refresh_directory) if File.exist?(@refresh_directory)
  end

  test "records snapshots for every market even when none need refreshing" do
    market = { healthy: true, source_date: Date.new(2026, 7, 31) }
    checker = Stock::DataStatus.allocate
    checker.stub(:call, Stock::AREAS.index_with { market }) do
      captured = []

      Stock::DataStatus.stub(:new, ->(*) { checker }) do
        Stock::SignalSnapshot.stub(:capture!, ->(area) { captured << area; 2 }) do
          output, = capture_io { invoke_daily_refresh }
          assert_match(/Captured rows: \{"bj" => 2, "sh" => 2, "sz" => 2\}/, output)
          assert_match(/Stored history rows:/, output)
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
        Stock::SignalSnapshot.stub(:capture!, 1) do
          Rake::Task[:refresh].stub(:invoke, ->(*areas) { refreshed.concat(areas) }) do
            invoke_daily_refresh
          end
        end
      end

      assert_equal [Stock::SHSTK], refreshed
      assert_equal 2, call_count
    end
  end

  test "fails instead of reporting success when a market captures no snapshots" do
    market = { healthy: true, source_date: Date.new(2026, 7, 31) }
    checker = Stock::DataStatus.allocate

    checker.stub(:call, Stock::AREAS.index_with { market }) do
      Stock::DataStatus.stub(:new, ->(*) { checker }) do
        capture = ->(area) { area == Stock::BJSTK ? 0 : 1 }
        Stock::SignalSnapshot.stub(:capture!, capture) do
          error = assert_raises(SystemExit) { capture_io { invoke_daily_refresh } }
          assert_equal 1, error.status
        end
      end
    end
  end

  test "backs up before capturing snapshots even when no recalculation is needed" do
    market = { healthy: true, source_date: Date.new(2026, 7, 31) }
    checker = Stock::DataStatus.allocate
    events = []

    checker.stub(:call, Stock::AREAS.index_with { market }) do
      Stock::DataStatus.stub(:new, ->(*) { checker }) do
        Stock::SignalSnapshot.stub(:capture!, ->(_area) { events << :snapshot; 1 }) do
          capture_io { invoke_daily_refresh(backup: -> { events << :backup }) }
        end
      end
    end

    assert_equal :backup, events.first
    assert_equal 1, events.count(:backup)
  end

  private

  def invoke_daily_refresh(backup: -> {})
    refresh_run = Stock::RefreshRun.new(
      lock_path: File.join(@refresh_directory, "refresh.lock"),
      status_path: File.join(@refresh_directory, "status.json")
    )
    Stock::RefreshRun.stub(:new, ->(*) { refresh_run }) do
      Rake::Task[:database_backup].stub(:invoke, backup) do
        Rake::Task["daily_refresh"].invoke
      end
    end
  end
end
