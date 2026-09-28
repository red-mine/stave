require "test_helper"

class StockRefreshRunTest < ActiveSupport::TestCase
  test "records successful and failed refresh attempts" do
    Dir.mktmpdir do |directory|
      runner = build_runner(directory)
      assert_equal :done, runner.call { :done }
      assert_equal "succeeded", runner.status[:state]
      assert_equal "scheduled", runner.status[:source]
      assert_equal "test", runner.status[:environment]
      assert runner.status[:finished_at].present?

      assert_raises(RuntimeError) { runner.call { raise "source unavailable" } }
      assert_equal "failed", runner.status[:state]
      assert_equal "source unavailable", runner.status[:error]
    end
  end

  test "records a failure that happened before the Rails stage" do
    Dir.mktmpdir do |directory|
      now = Time.zone.parse("2026-09-27 12:35:30")
      runner = build_runner(directory, clock: -> { now })
      runner.record_failure!("TongdaXin data update failed (exit code 1)")

      assert_equal "failed", runner.status[:state]
      assert_equal "TongdaXin data update failed (exit code 1)", runner.status[:error]
      assert_equal "scheduled", runner.status[:source]
      assert_equal now.iso8601, runner.status[:started_at]
      assert_equal now.iso8601, runner.status[:finished_at]
      assert_equal "failed", runner.scheduled_status[:state]
    end
  end

  test "uses the runner start time from the environment for a pre-Rails failure" do
    Dir.mktmpdir do |directory|
      now = Time.zone.parse("2026-09-27 12:35:30")
      runner = build_runner(directory, clock: -> { now })
      ENV["STOCK_REFRESH_STARTED_AT"] = "2026-09-27T12:30:01Z"

      runner.record_failure!("TongdaXin data update failed (exit code 1)")

      assert_equal "2026-09-27T12:30:01Z", runner.status[:started_at]
      assert_equal now.iso8601, runner.status[:finished_at]
    ensure
      ENV.delete("STOCK_REFRESH_STARTED_AT")
    end
  end

  test "falls back to the current time when the runner start time is not a timestamp" do
    Dir.mktmpdir do |directory|
      now = Time.zone.parse("2026-09-27 12:35:30")
      runner = build_runner(directory, clock: -> { now })
      ENV["STOCK_REFRESH_STARTED_AT"] = "not-a-timestamp"

      runner.record_failure!("TongdaXin data update failed (exit code 1)")

      assert_equal now.iso8601, runner.status[:started_at]
    ensure
      ENV.delete("STOCK_REFRESH_STARTED_AT")
    end
  end

  test "refuses a concurrent refresh" do
    Dir.mktmpdir do |directory|
      runner = build_runner(directory)
      Dir.mkdir(File.join(directory, "refresh.lock"))

      assert_raises(Stock::RefreshRun::AlreadyRunning) { runner.call { flunk "must not run" } }
    end
  end

  test "recovers an empty lock left beyond the scheduler time limit" do
    Dir.mktmpdir do |directory|
      now = Time.zone.parse("2026-08-02 23:30:00")
      lock_path = File.join(directory, "refresh.lock")
      Dir.mkdir(lock_path)
      stale_time = (now - 6.hours).to_time
      File.utime(stale_time, stale_time, lock_path)
      runner = build_runner(directory, clock: -> { now })

      assert_equal :done, runner.call { :done }
      assert_equal true, runner.status[:recovered_stale_lock]
      assert_equal "succeeded", runner.status[:state]
    end
  end

  test "preserves the last scheduled result across later manual runs" do
    Dir.mktmpdir do |directory|
      scheduled = build_runner(directory)
      scheduled.call { :scheduled }

      manual = build_runner(directory, source: "manual")
      manual.call { :manual }

      assert_equal "manual", manual.status[:source]
      assert_equal "succeeded", manual.scheduled_status[:state]
      assert_equal "scheduled", manual.scheduled_status[:source]
    end
  end

  private

  def build_runner(directory, clock: -> { Time.current }, source: "scheduled")
    Stock::RefreshRun.new(
      lock_path: File.join(directory, "refresh.lock"),
      status_path: File.join(directory, "status.json"),
      scheduled_status_path: File.join(directory, "scheduled-status.json"),
      source: source,
      clock: clock
    )
  end
end
