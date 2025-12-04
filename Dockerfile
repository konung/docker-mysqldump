# Stage 1: Build stage (compile native gems)
FROM ruby:3.4.7-slim-trixie AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libmariadb-dev-compat libmariadb-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs=4 --retry=3

# Stage 2: Runtime stage (minimal)
FROM ruby:3.4.7-slim-trixie

ENV APP_PATH=/app
WORKDIR $APP_PATH

# Runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    mariadb-client \
    libmariadb3 \
    p7zip-full \
    cron \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Copy installed gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application
COPY . .

VOLUME ["/path_to_backups_dir_on_host"]

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
ENV MARIADB_SSL=0

RUN touch "$CRON_LOG_PATH" && chmod +x -R /app

CMD ["bash", "-c", "bundle exec whenever --update-crontab && cron -f"]
