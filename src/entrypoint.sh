#!/bin/sh

# Copyright 2021 - Igor VISI < igorvisi.com >
# SPDX-License-Identifier: MPL-2.0

# Portions of this file are taken from github.com/futurice/docker-volume-backup and github.com/offen/docker-volume-backup
# See NOTICE for information about authors and licensing.

set -e

# Write cronjob env to file, fill in sensible defaults, and read them back in
cat <<EOF > env.sh
BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"
BACKUP_CRON_EXPRESSION="${BACKUP_CRON_EXPRESSION:-@daily}"
BACKUP_FILENAME=${BACKUP_FILENAME:-"backup-%Y-%m-%dT%H-%M-%S.tar.gz"}

BACKUP_ARCHIVE="${BACKUP_ARCHIVE:-/archive}"
BACKUP_UID=${BACKUP_UID:-0}
BACKUP_GID=${BACKUP_GID:-$BACKUP_UID}

BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-}"
BACKUP_PRUNING_LEEWAY="${BACKUP_PRUNING_LEEWAY:-10m}"
BACKUP_ARCHIVE_RETENTION_DAYS="${BACKUP_ARCHIVE_RETENTION_DAYS:1}"

BACKUP_CUSTOM_LABEL="${BACKUP_CUSTOM_LABEL:-}"

AWS_S3_BUCKET_NAME="${AWS_S3_BUCKET_NAME:-}"
AWS_ENDPOINT="${AWS_ENDPOINT:-s3.amazonaws.com}"
AWS_ENDPOINT_PROTO="${AWS_ENDPOINT_PROTO:-https}"

GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"

BACKUP_STOP_CONTAINER_LABEL="${BACKUP_STOP_CONTAINER_LABEL:-true}"

MC_GLOBAL_OPTIONS="${MC_GLOBAL_OPTIONS:-}"
EOF
chmod a+x env.sh
source env.sh

mc $MC_GLOBAL_OPTIONS alias set backup-target "$AWS_ENDPOINT_PROTO://$AWS_ENDPOINT" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY"

# Add our cron entry, and direct stdout & stderr to Docker commands stdout
echo "Installing cron.d entry with expression $BACKUP_CRON_EXPRESSION."
echo "$BACKUP_CRON_EXPRESSION backup 2>&1" | crontab -

# Let cron take the wheel
echo "Starting cron in foreground."
crond -f -l 8
