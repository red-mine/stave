namespace :retention do
  desc "Remove stale public preview status and tunnel logs"
  task cleanup_preview: :environment do
    retention_days = ENV.fetch("STOCK_PREVIEW_RETENTION_DAYS", "7").to_i
    cutoff = retention_days.days.ago
    Rails.root.join("tmp").glob("public-preview*").each do |path|
      next unless path.file? && path.mtime < cutoff

      Rails.logger.info "Removing stale preview file: #{path}"
      path.delete
    end
    Rails.root.join("tmp").glob("cloudflared*").each do |path|
      next unless path.file? && path.mtime < cutoff

      Rails.logger.info "Removing stale tunnel log: #{path}"
      path.delete
    end
  end

  desc "Trim public-preview-monitor.log to the newest 1000 lines"
  task trim_monitor_log: :environment do
    log_path = Rails.root.join("log", "public-preview", "monitor.log")
    next unless log_path.file?

    lines = log_path.readlines
    return if lines.size <= 1000

    log_path.write(lines.last(1000).join)
  end
end

desc "Run all retention tasks"
task retention: ["retention:cleanup_preview", "retention:trim_monitor_log"]
