require "json"

module Stock
  class RefreshRun
    class AlreadyRunning < StandardError; end

    def initialize(
      lock_path: Rails.root.join("tmp", "stock-refresh.lock"),
      status_path: Rails.root.join("tmp", "stock-refresh-status.json"),
      source: ENV.fetch("STOCK_REFRESH_SOURCE", "application"),
      environment: Rails.env,
      stale_after: 5.hours,
      clock: -> { Time.current }
    )
      @lock_path = Pathname.new(lock_path)
      @status_path = Pathname.new(status_path)
      @source = source
      @environment = environment.to_s
      @stale_after = stale_after
      @clock = clock
    end

    def call
      FileUtils.mkdir_p(@lock_path.dirname)
      acquire_lock

      started_at = @clock.call
      write_status(run_status(state: "running", started_at: started_at))
      begin
        result = yield
        write_status(run_status(state: "succeeded", started_at: started_at, finished_at: @clock.call))
        result
      rescue Exception => error # record task failures before Rake exits
        write_status(run_status(state: "failed", started_at: started_at, finished_at: @clock.call, error: error.message))
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

    def acquire_lock
      @recovered_stale_lock = false
      Dir.mkdir(@lock_path)
    rescue Errno::EEXIST
      raise AlreadyRunning, "A stock refresh is already running" unless stale_lock?

      begin
        Dir.rmdir(@lock_path)
        @recovered_stale_lock = true
        Dir.mkdir(@lock_path)
      rescue Errno::ENOENT, Errno::EEXIST, Errno::ENOTEMPTY
        raise AlreadyRunning, "A stock refresh is already running"
      end
    end

    def stale_lock?
      @clock.call - @lock_path.mtime > @stale_after
    rescue SystemCallError
      false
    end

    def run_status(attributes)
      attributes.merge(source: @source, environment: @environment).tap do |status|
        status[:recovered_stale_lock] = true if @recovered_stale_lock
      end
    end

    def write_status(attributes)
      FileUtils.mkdir_p(@status_path.dirname)
      temporary = Pathname.new("#{@status_path}.tmp")
      temporary.write(JSON.pretty_generate(attributes.transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601 : value }))
      FileUtils.mv(temporary, @status_path)
    end
  end
end
