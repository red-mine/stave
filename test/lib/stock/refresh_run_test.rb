require "test_helper"

class StockRefreshRunTest < ActiveSupport::TestCase
  test "records successful and failed refresh attempts" do
    Dir.mktmpdir do |directory|
      runner = build_runner(directory)
      assert_equal :done, runner.call { :done }
      assert_equal "succeeded", runner.status[:state]
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

  private

  def build_runner(directory)
    Stock::RefreshRun.new(
      lock_path: File.join(directory, "refresh.lock"),
      status_path: File.join(directory, "status.json")
    )
  end
end
