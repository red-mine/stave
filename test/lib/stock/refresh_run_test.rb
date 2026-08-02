require "test_helper"

class StockRefreshRunTest < ActiveSupport::TestCase
  test "records successful and failed refresh attempts" do
    Dir.mktmpdir do |directory|
      runner = build_runner(directory)
      assert_equal :done, runner.call { :done }
      assert_equal "succeeded", runner.status[:state]
      assert_equal "scheduled", runner.status[:source]
      assert runner.status[:finished_at].present?

      assert_raises(RuntimeError) { runner.call { raise "source unavailable" } }
      assert_equal "failed", runner.status[:state]
      assert_equal "source unavailable", runner.status[:error]
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

  private

  def build_runner(directory, clock: -> { Time.current })
    Stock::RefreshRun.new(
      lock_path: File.join(directory, "refresh.lock"),
      status_path: File.join(directory, "status.json"),
      source: "scheduled",
      clock: clock
    )
  end
end
