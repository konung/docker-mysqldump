FROM ruby:3.0

ENV APP_PATH=/app
WORKDIR $APP_PATH
COPY . .
VOLUME [ "/path_to_backups_dir_on_host"]


RUN apt-get update -y
RUN apt-get install -y tzdata rsync build-essential mariadb-client \
    libmariadb-dev-compat libmariadb-dev p7zip-full cron nano iputils-ping iproute2

ENV TZ="America/Chicago"
ENV SQL_SERVER_TO_BACKUP_NAME=sql-replica-1
ENV SQL_SERVER_TO_BACKUP_FQDN=sql-replica-1.example.com
ENV COMMA_SEP_LIST_DBS_TO_BACKUP_LEAVE_BLANK_FOR_ALL=
ENV SQL_BACKUP_USER=CHANGE_ME_MYSQL_DUMP_USER
ENV SQL_BACKUP_PASS=CHANGE_ME_MYSQL_DUMP_PASS
ENV TMP_BACKUP_TO_DIR=/tmp/sqldata/
ENV FINAL_COPY_TO_DIR=/path_to_backups_dir_on_host/
ENV CRON_LOG_PATH=/var/log/cron.log
ENV BACKUP_FREQUENCY_MINS=60


RUN touch "$CRON_LOG_PATH"
RUN chmod +x -R /app
RUN bundle install

CMD bash -c "bundle exec whenever --update-crontab && cron -f"