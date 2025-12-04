#   Author:       Nick Gorbikoff
#   Date:         September 8, 2021
#   Email:        nick.gorbikoff@gmail.com
#   Description:  This lib is used for useful little snippets used for backup.
#   Requires:     mysql2 gem and mariadb-dump installed system wide.
require "rubygems"
require "mysql2"
require "fileutils"
require "parallel"
require "tty-logger"
require "tty-spinner"
require "tty-table"
require "pastel"

class BackupLib
  SQL_SERVER_TO_BACKUP_NAME = ENV["SQL_SERVER_TO_BACKUP_NAME"]
  SQL_SERVER_TO_BACKUP_FQDN = ENV["SQL_SERVER_TO_BACKUP_FQDN"]
  SQL_BACKUP_USER = ENV["SQL_BACKUP_USER"]
  SQL_BACKUP_PASS = ENV["SQL_BACKUP_PASS"]
  COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL = ENV["COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL"]

  # Databases to always exclude from backup (system/virtual schemas)
  EXCLUDED_DATABASES = %w[information_schema performance_schema sys].freeze

  DAY_OF_WEEK = Time.now.strftime("%A")
  HOUR_OF_DAY = Time.now.strftime("%H")

  TMP_BACKUP_TO_PATH = File.join(ENV["TMP_BACKUP_TO_DIR"], DAY_OF_WEEK, HOUR_OF_DAY, "/")
  FINAL_BACKUP_STORAGE_PATH = File.join(ENV["FINAL_COPY_TO_DIR"], SQL_SERVER_TO_BACKUP_NAME, DAY_OF_WEEK, "/")

  def logger
    @logger ||= TTY::Logger.new do |config|
      config.level = :info
      config.handlers = [[:console, {output: $stdout}]]
    end
  end

  def pastel
    @pastel ||= Pastel.new
  end

  def db_connection
    @db_connection ||= Mysql2::Client.new(
      host: SQL_SERVER_TO_BACKUP_FQDN,
      username: SQL_BACKUP_USER,
      password: SQL_BACKUP_PASS
    )
  end

  def has_myisam_tables?(db_name)
    result = db_connection.query(<<~SQL)
      SELECT COUNT(*) as cnt FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = '#{db_name}'
      AND ENGINE = 'MyISAM'
    SQL
    result.first["cnt"] > 0
  end

  def classify_databases(databases)
    innodb_only = []
    has_myisam = []
    table_rows = []

    databases.each do |db|
      if has_myisam_tables?(db)
        has_myisam << db
        table_rows << [db, pastel.yellow("MyISAM"), pastel.yellow("Pause replication")]
      else
        innodb_only << db
        table_rows << [db, pastel.green("InnoDB"), pastel.green("--single-transaction")]
      end
    end

    table = TTY::Table.new(
      header: [pastel.bold("Database"), pastel.bold("Engine"), pastel.bold("Strategy")],
      rows: table_rows
    )
    puts table.render(:unicode, padding: [0, 1])

    {innodb_only: innodb_only, has_myisam: has_myisam}
  end

  def stop_replica_sql_thread!
    spinner = TTY::Spinner.new("[:spinner] Stopping replica SQL thread...", format: :dots)
    spinner.auto_spin
    db_connection.query("STOP SLAVE SQL_THREAD")
    spinner.success(pastel.green("stopped"))
    true
  rescue Mysql2::Error => e
    if e.message.include?("REPLICATION SLAVE ADMIN")
      spinner.error(pastel.yellow("skipped - missing REPLICATION SLAVE ADMIN privilege"))
      logger.warn "Cannot pause replication - backup user needs REPLICATION SLAVE ADMIN privilege"
    else
      spinner.error(pastel.red("failed: #{e.message}"))
    end
    false
  end

  def start_replica_sql_thread!
    spinner = TTY::Spinner.new("[:spinner] Starting replica SQL thread...", format: :dots)
    spinner.auto_spin
    db_connection.query("START SLAVE SQL_THREAD")
    spinner.success(pastel.green("started - will catch up automatically"))
    true
  rescue Mysql2::Error => e
    if e.message.include?("REPLICATION SLAVE ADMIN")
      spinner.success(pastel.dim("skipped - was not stopped"))
    else
      spinner.error(pastel.red("failed: #{e.message}"))
      logger.error "Failed to restart replication", error: e.message
    end
    false
  end

  def replica_seconds_behind
    result = db_connection.query("SHOW SLAVE STATUS")
    row = result.first
    row ? row["Seconds_Behind_Master"] : nil
  end

  def create_all_storage_locations!
    logger.info "Creating temp storage locations in #{TMP_BACKUP_TO_PATH}"
    FileUtils.mkdir_p TMP_BACKUP_TO_PATH
    logger.info "Creating final storage locations in #{FINAL_BACKUP_STORAGE_PATH}"
    FileUtils.mkdir_p FINAL_BACKUP_STORAGE_PATH
  end

  def copy_from_tmp_to_final_location!
    logger.info "Copy from temporary location to final location: from - #{TMP_BACKUP_TO_PATH}, to - #{FINAL_BACKUP_STORAGE_PATH}"
    FileUtils.cp_r(TMP_BACKUP_TO_PATH, FINAL_BACKUP_STORAGE_PATH, verbose: true)
  end

  def cleanup_tmp_dump_location!
    logger.info "Cleanup temporary dump location: #{TMP_BACKUP_TO_PATH}"
    FileUtils.rm_rf(TMP_BACKUP_TO_PATH, verbose: true)
  end

  def backup_all_databases(host: SQL_SERVER_TO_BACKUP_FQDN,
    user: SQL_BACKUP_USER,
    pass: SQL_BACKUP_PASS,
    backup_path_dir: TMP_BACKUP_TO_PATH)
    @failed_backups = []

    puts ""
    puts pastel.bold.cyan("MariaDB Backup")
    puts pastel.dim("─" * 60)
    logger.info "Connecting to server", server: host

    # Get a list of DBs to backup
    dbs_from_query = db_connection.query("SHOW DATABASES").map { |row| row["Database"] }

    # Check to see if LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL is set
    env_db_list = COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL.to_s.split(",").compact.map(&:strip)
    dbs_to_backup = env_db_list.empty? ? dbs_from_query : env_db_list

    # Filter out excluded system databases
    excluded = dbs_to_backup & EXCLUDED_DATABASES
    dbs_to_backup -= EXCLUDED_DATABASES

    logger.info "Using filtered database list", count: env_db_list.size if env_db_list.any?

    logger.info "Excluding system databases", excluded: excluded if excluded.any?

    logger.info "Found databases to backup", count: dbs_to_backup.size

    # Classify databases by storage engine
    puts ""
    puts pastel.bold("Database Classification")
    puts pastel.dim("─" * 60)
    classified = classify_databases(dbs_to_backup)

    # Phase 1: Backup InnoDB-only databases (parallel, no locking)
    if classified[:innodb_only].any?
      puts ""
      puts pastel.bold.green("▶ PHASE 1: InnoDB Databases")
      puts pastel.dim("  Strategy: --single-transaction (no locking, parallel)")
      puts pastel.dim("─" * 60)

      backup_databases(
        databases: classified[:innodb_only],
        host: host,
        user: user,
        pass: pass,
        backup_path_dir: backup_path_dir,
        use_single_transaction: true
      )
    end

    # Phase 2: Backup MyISAM databases (with replica pause)
    if classified[:has_myisam].any?
      puts ""
      puts pastel.bold.yellow("▶ PHASE 2: MyISAM Databases")
      puts pastel.dim("  Strategy: Pause replication SQL thread during backup")
      puts pastel.dim("─" * 60)

      begin
        stop_replica_sql_thread!

        backup_databases(
          databases: classified[:has_myisam],
          host: host,
          user: user,
          pass: pass,
          backup_path_dir: backup_path_dir,
          use_single_transaction: false
        )
      ensure
        start_replica_sql_thread!
        lag = replica_seconds_behind
        if lag
          logger.info "Replication lag", seconds: lag
        else
          logger.warn "Could not determine replication lag"
        end
      end
    end

    # Final status
    puts ""
    puts pastel.dim("─" * 60)

    if @failed_backups.empty?
      puts pastel.bold.green("✓ All backups completed successfully!")
    else
      puts pastel.bold.red("✗ Backup completed with #{@failed_backups.size} failure(s):")
      @failed_backups.each do |failure|
        puts pastel.red("  • #{failure[:db]}: #{failure[:error]}")
      end
      puts ""
      logger.error "Backup failures", failed: @failed_backups.map { |f| f[:db] }
    end
    puts ""

    @failed_backups.empty?
  end

  def backup_databases(databases:, host:, user:, pass:, backup_path_dir:, use_single_transaction:)
    transaction_flag = use_single_transaction ? "--single-transaction --skip-lock-tables" : ""
    ssl_flag = (ENV.fetch("MARIADB_SSL", "0") == "1") ? "" : "--ssl=0"
    network_flags = "--quick --max-allowed-packet=1G --net-buffer-length=32768"

    Parallel.each(databases, in_threads: Parallel.processor_count) do |db|
      backup_single_database(
        db: db,
        host: host,
        user: user,
        pass: pass,
        backup_path_dir: backup_path_dir,
        flags: "#{transaction_flag} #{ssl_flag} #{network_flags}".strip
      )
    end
  end

  def backup_single_database(db:, host:, user:, pass:, backup_path_dir:, flags:)
    start_time = Time.now
    backup_file_name = "#{backup_path_dir}#{db}"
    backup_file_path = "#{backup_file_name}.sql"
    backup_archive_path = "#{backup_file_name}.7z"
    error_file_path = "#{backup_file_name}.err"

    spinner = TTY::Spinner.new(
      "[:spinner] #{db} - :status",
      format: :dots,
      hide_cursor: true
    )

    # Dump database (capture stderr separately)
    spinner.update(status: "dumping...")
    spinner.auto_spin
    cmd_dump = "mariadb-dump #{flags} -h#{host} -u#{user} -p#{pass} #{db} > #{backup_file_path} 2>#{error_file_path}"
    dump_success = system(cmd_dump)

    unless dump_success
      error_msg = File.exist?(error_file_path) ? File.read(error_file_path).strip.lines.first&.strip : "unknown error"
      @failed_backups << {db: db, error: error_msg}
      spinner.error(pastel.red("dump failed"))
      FileUtils.rm_f([backup_file_path, error_file_path])
      return
    end

    FileUtils.rm_f(error_file_path)

    # Compress with 7zip
    spinner.update(status: "compressing...")
    cmd_7zip = "7z a -sdel #{backup_archive_path} #{backup_file_path} -mx1 > /dev/null 2>&1"
    zip_success = system(cmd_7zip)

    elapsed = (Time.now - start_time).round(1)

    if zip_success
      file_size = File.exist?(backup_archive_path) ? format_size(File.size(backup_archive_path)) : "?"
      spinner.success(pastel.green("done") + pastel.dim(" (#{file_size}, #{elapsed}s)"))
    else
      @failed_backups << {db: db, error: "7zip compression failed"}
      spinner.error(pastel.red("compression failed"))
    end
  end

  def format_size(bytes)
    units = %w[B KB MB GB TB]
    return "0 B" if bytes == 0

    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = units.size - 1 if exp > units.size - 1

    format("%.1f %s", bytes.to_f / (1024**exp), units[exp])
  end
end
