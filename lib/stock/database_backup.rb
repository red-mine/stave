require "sqlite3"

module Stock
  class DatabaseBackup
    def initialize(connection: ActiveRecord::Base.connection)
      @connection = connection
    end

    def call(destination)
      destination_database = SQLite3::Database.new(destination.to_s)
      backup = SQLite3::Backup.new(destination_database, "main", @connection.raw_connection, "main")
      status = backup.step(-1)
      return if status == SQLite3::Constants::ErrorCode::DONE

      raise SQLite3::Exception, "SQLite backup did not complete (status #{status})"
    ensure
      backup&.finish
      destination_database&.close
    end
  end
end
