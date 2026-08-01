require "pathname"
require "securerandom"
require "sqlite3"

module Stock
  class DatabaseBackup
    def initialize(connection: ActiveRecord::Base.connection)
      @connection = connection
    end

    def call(destination)
      destination = Pathname.new(destination)
      raise Errno::EEXIST, destination.to_s if destination.exist?

      temporary = destination.dirname.join(".#{destination.basename}.#{SecureRandom.hex(6)}.tmp")
      destination_database = SQLite3::Database.new(temporary.to_s)
      backup = SQLite3::Backup.new(destination_database, "main", @connection.raw_connection, "main")
      status = backup.step(-1)
      unless status == SQLite3::Constants::ErrorCode::DONE
        raise SQLite3::Exception, "SQLite backup did not complete (status #{status})"
      end

      backup.finish
      backup = nil
      integrity = destination_database.get_first_value("PRAGMA integrity_check")
      raise SQLite3::Exception, "SQLite backup failed integrity check: #{integrity}" unless integrity == "ok"

      destination_database.close
      destination_database = nil
      File.link(temporary, destination)
      destination
    ensure
      backup&.finish
      destination_database&.close
      temporary&.delete if temporary&.exist?
    end
  end
end
