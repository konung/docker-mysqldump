#   Author:       Nick Gorbikoff
#   Date:         September 8, 2021
#   Email:        nick.gorbikoff@gmail.com
#   Description:  Backup sql-replica-1 server

require_relative 'backuplib'
backup_lib = BackupLib.new
backup_lib.create_all_storage_locations!
backup_lib.backup_all_databases
backup_lib.copy_from_tmp_to_final_location!
backup_lib.cleanup_tmp_dump_location!
