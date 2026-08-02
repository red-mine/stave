require "json"

module Stock
  class RefreshRun
    class AlreadyRunning < StandardError; end

    def initialize(
      lock_path: Rails.root.join("tmp", "stock-refresh.lock"),
      status_path: Rails.root.join("tmp", "stock-refresh-status.json"),
      clock: -> { Time.current }
    )
      @lock_path = Pathname.new(lock_path)
      @status_path = Pathname.new(status_path)
      @clock = clock
    end

    def call
      FileUtils.mkdir_p(@lock_path.dirname)
      begin
        Dir.mkdir(@lock_path)
      rescue Errno::EEXIST
        raise AlreadyRunning, "A stock refresh is already running"
      end

      started_at = @clock.call
      write_status(state: "running", started_at: started_at)
      begin
        result = yield
        write_status(state: "succeeded", started_at: started_at, finished_at: @clock.call)
        result
      rescue Exception => error # record task failures before Rake exits
        write_status(state: "failed", started_at: started_at, finished_at: @clock.call, error: error.message)
        raise
      ensure
        Dir.rmdir(@lock_path) if @lock_path.directory?
      end
    end

    def status
      return {} unless @status_path.file?

      JSON.parse(@status_path.read, symbolize_names: true)
    rescue JSON::ParserError, SystemCallError
      {}
    end

    private

    def write_status(attributes)
      FileUtils.mkdir_p(@status_path.dirname)
      temporary = Pathname.new("#{@status_path}.tmp")
      temporary.write(JSON.pretty_generate(attributes.transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601 : value }))
      FileUtils.mv(temporary, @status_path)
    end
  end
end
