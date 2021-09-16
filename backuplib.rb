#   Author:       Nick Gorbikoff
#   Date:         September 8, 2021
#   Email:        nick.gorbikoff@gmail.com
#   Description:  This lib is used for usefull little snippelts used for backup.
#   Requires:     mysql gem and mysqldump installed system wide.
require 'rubygems'
require 'logger'
require 'mysql2'
require 'fileutils'

class BackupLib
  SQL_SERVER_TO_BACKUP_NAME = ENV['SQL_SERVER_TO_BACKUP_NAME']
  SQL_SERVER_TO_BACKUP_FQDN = ENV['SQL_SERVER_TO_BACKUP_FQDN']
  SQL_BACKUP_USER = ENV['SQL_BACKUP_USER']
  SQL_BACKUP_PASS = ENV['SQL_BACKUP_PASS']
  COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL = ENV['COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL']

  DAY_OF_WEEK = Time.now.strftime('%A')
  HOUR_OF_DAY = Time.now.strftime('%H')

  TMP_BACKUP_TO_PATH = File.join(ENV['TMP_BACKUP_TO_DIR'], DAY_OF_WEEK, HOUR_OF_DAY, '/')
  FINAL_BACKUP_STORAGE_PATH = File.join(ENV['FINAL_COPY_TO_DIR'], SQL_SERVER_TO_BACKUP_NAME, DAY_OF_WEEK, '/')

  def logger
    @logger ||= Logger.new(STDOUT, :debug)
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
    #### App itself
    logger.info "Setup MySQL connection to server : #{host}"
    my = Mysql2::Client.new(host: host, username: user, password: pass)
    # You can do any SSL stuff before the real_connect
    # args: hostname, username, password, database
    # my.real_connect(host,user,pass)

    # Get a list of DBs to backup
    logger.info 'List available DBs'
    dbs_from_query = my.query('SHOW DATABASES')

    # Check to see if LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL is set
    logger.info "Check if COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL (#{COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL}) is set to  anything? "
    env_db_list = COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL.split(',').compact.map(&:strip)

    dbs_to_backup = env_db_list.empty? ? dbs_from_query : env_db_list

    logger.info "Will backup #{dbs_to_backup}"

    # get a name run a sql dump
    dbs_to_backup.each do |row|
      db = row['Database'].to_s

      # Skipping larger backups during dev phase
      # next unless db == 'support_development'

      start_time = Time.now
      logger.info ''
      logger.info '##########################################'
      logger.info "Starting to backup #{db} at #{start_time}"
      backup_file_name =  "#{backup_path_dir}#{db}"
      backup_file_path =  "#{backup_file_name}.sql"
      backup_archive_path =  "#{backup_file_name}.7z"
      cmd_mysql = "mysqldump -h#{host} -u#{user} -p#{pass} #{db} > #{backup_file_path}"
      logger.debug cmd_mysql
      system(cmd_mysql)

      cmd_7zip = "7z a -sdel #{backup_archive_path} #{backup_file_path} -mx1  "
      logger.debug cmd_7zip
      system(cmd_7zip)
      finish_time = Time.now
      logger.info "Finished backing up #{db} at #{finish_time}."
      logger.info "It took #{finish_time - start_time}"
      logger.info '##########################################'
      logger.info ''
    end
  end
end
