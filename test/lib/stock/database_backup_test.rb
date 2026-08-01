require "test_helper"
require "tmpdir"

class DatabaseBackupTest < ActiveSupport::TestCase
  test "includes committed data that is still in the WAL" do
    Dir.mktmpdir do |directory|
      source_path = File.join(directory, "source.sqlite3")
      backup_path = File.join(directory, "backup.sqlite3")
      source = SQLite3::Database.new(source_path)
      source.execute("PRAGMA journal_mode = WAL")
      source.execute("CREATE TABLE observations (value TEXT NOT NULL)")
      source.execute("INSERT INTO observations (value) VALUES (?)", ["committed"])

      connection = Struct.new(:raw_connection).new(source)
      Stock::DatabaseBackup.new(connection: connection).call(backup_path)

      backup = SQLite3::Database.new(backup_path)
      assert_equal [["committed"]], backup.execute("SELECT value FROM observations")
    ensure
      backup&.close
      source&.close
    end
  end
end
