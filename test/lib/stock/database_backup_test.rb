require "test_helper"
require "tmpdir"

class DatabaseBackupTest < ActiveSupport::TestCase
  test "includes committed data that is still in the WAL" do
    Dir.mktmpdir do |directory|
      source_path = File.join(directory, "source.sqlite3")
      backup_path = Pathname.new(directory).join("backup.sqlite3")
      source = SQLite3::Database.new(source_path)
      source.execute("PRAGMA journal_mode = WAL")
      source.execute("CREATE TABLE observations (value TEXT NOT NULL)")
      source.execute("INSERT INTO observations (value) VALUES (?)", ["committed"])

      connection = Struct.new(:raw_connection).new(source)
      Stock::DatabaseBackup.new(connection: connection).call(backup_path)

      backup = SQLite3::Database.new(backup_path.to_s)
      assert_equal [["committed"]], backup.execute("SELECT value FROM observations")
      assert_empty Dir.glob(File.join(directory, ".backup.sqlite3.*.tmp"))
    ensure
      backup&.close
      source&.close
    end
  end

  test "does not overwrite an existing backup" do
    Dir.mktmpdir do |directory|
      backup_path = File.join(directory, "backup.sqlite3")
      File.binwrite(backup_path, "existing backup")

      error = assert_raises(Errno::EEXIST) do
        Stock::DatabaseBackup.new.call(backup_path)
      end

      assert_includes error.message, backup_path
      assert_equal "existing backup", File.binread(backup_path)
    end
  end

  test "prunes only auto-generated backups beyond the retention limit" do
    Dir.mktmpdir do |directory|
      (1..9).each do |index|
        name = format("stock-20260801-%06d-001.sqlite3", index)
        File.binwrite(File.join(directory, name), "backup #{index}")
      end
      File.binwrite(File.join(directory, "ui-before-manual.sqlite3"), "manual backup")

      pruned = Stock::DatabaseBackup.prune(directory, keep: 7)

      assert_equal 2, pruned
      remaining = Dir.glob(File.join(directory, "stock-*.sqlite3")).sort
      assert_equal 7, remaining.length
      assert File.file?(File.join(directory, "ui-before-manual.sqlite3"))
    end
  end
end
