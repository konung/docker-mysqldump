# docker-mysqldump

Docker Hub - [konung/mysqldump](https://hub.docker.com/r/konung/mysqldump)

Github - [konung/docker-mysqldump](https://github.com/konung/docker-mysqldump) (See GitHub for license and disclaimer)

```shell
docker pull konung/mysqldump
```

Docker container + mysql dump + ruby script
You can backup ALL dbs from your MySQL/MariaDB server, or just several.

## Important points

- ENV variables have to be defined in Fudging UPPER_CASE, otherwise whenever + cron won't pick it up
- Everything should be marked as `chmod +x`
- `TZ` needs to be set to Chicago, otherwise container thinks it's in Greenwich
- `TMP_BACKUP_TO_DIR=/tmp/sqldata/` - while script cleans up after itself, better to save to temp location that will be wiped on container restart
- Cron log is not working, and I can't find a good reason why. Some suggest running it in privileged mode with rsysloged — but I don't want to do that, just for that.
- `FINAL_COPY_TO_DIR=/path_to_backups_dir_on_host/` needs to be mounted and point to final destination on backup. Use `symlink`, `nfs` or `smb`. If not script will start saving locally, wherever `sqldata` is mapped to on the container or host server ( if the ENV mapped during `container run`) .

## Setup

- This was developed to be run within Synology NAS, but no reason it should be able to run in any other Docker host environment.
- If you want to run on your MacBook/Windows/Linux desktop, I recommend using .env file to override any Dockerfile ENV variables, using .evn file. Synology / QNAP NAS should give you ability to do in GUI.
- [Refer to Dockerfile](https://github.com/konung/docker-mysqldump/blob/main/Dockerfile), for available variables. But important ENV variables to override are:

  ```shell
  SQL_SERVER_TO_BACKUP_NAME=sql-replica-1
  SQL_SERVER_TO_BACKUP_FQDN=sql-replica-1.example.com
  SQL_BACKUP_USER=CHANGE_ME_MYSQL_DUMP_USER
  SQL_BACKUP_PASS=CHANGE_ME_MYSQL_DUMP_PASS
  FINAL_COPY_TO_DIR=/path_to_folder_on_host_where_to_save_backedup_files
  ```

- If you want to back up all databases on your server/cluster leave `COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL=` blank, otherwise specify comma separated list like so

```
COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL=great_db_production, another_great_db_development
```

## Example commands

Start container (demonizing, nameing, telling it to purge on exit, mounting volume, and passing env file from host)

```shell
docker run -itd --name mysql_backup_container --rm -v /Users/konung/Backup_folder:/path_to_backups_dir_on_host --env-file .env konung/synology-mysqldump:1.65
```

Log into container

```shell
docker exec -ti mysql_backup_container /bin/bash
```

Kill container (should be deleted automatically on exit/kill)

```shell
docker container kill mysql_backup_container
```
