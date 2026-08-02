require "json"

module Stock
  class RefreshSchedule
    def initialize(status_path: Rails.root.join("tmp", "stock-refresh-schedule.json"))
      @status_path = Pathname.new(status_path)
    end

    def status
      return {} unless @status_path.file?

      JSON.parse(@status_path.read, symbolize_names: true)
    rescue JSON::ParserError, SystemCallError
      {}
    end
  end
end
