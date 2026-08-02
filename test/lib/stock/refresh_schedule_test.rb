require "test_helper"

class StockRefreshScheduleTest < ActiveSupport::TestCase
  test "reads valid schedule metadata and tolerates missing or invalid files" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "schedule.json")
      schedule = Stock::RefreshSchedule.new(status_path: path)

      assert_equal({}, schedule.status)
      File.write(path, JSON.generate(enabled: true, time: "20:30"))
      assert_equal({ enabled: true, time: "20:30" }, schedule.status)
      File.write(path, "not json")
      assert_equal({}, schedule.status)
    end
  end
end
