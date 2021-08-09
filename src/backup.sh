#!/bin/sh

# Copyright 2021 - Igor VISI < igorvisi.com >
# SPDX-License-Identifier: MPL-2.0

# Portions of this file are taken from github.com/futurice/docker-volume-backup and github.com/offen/docker-volume-backup
# See NOTICE for information about authors and licensing.
source env.sh

function info {
  echo -e "\n[INFO] $1\n"
}

info "Preparing backup"
DOCKER_SOCK="/var/run/docker.sock"


if [ ! -z "$BACKUP_CUSTOM_LABEL" ]; then
  CUSTOM_LABEL="--filter label=$BACKUP_CUSTOM_LABEL"
fi

if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps -q \
    --filter "label=docker-volume-backup.stop-during-backup=true" $CUSTOM_LABEL \
    > "$TEMPFILE"
  CONTAINERS_TO_STOP="$(cat $TEMPFILE | tr '\n' ' ')"
  CONTAINERS_TO_STOP_TOTAL="$(cat $TEMPFILE | wc -l)"
  CONTAINERS_TOTAL="$(docker ps -q | wc -l)"
  rm "$TEMPFILE"
  echo "$CONTAINERS_TOTAL containers running on host in total."
  echo "$CONTAINERS_TO_STOP_TOTAL containers marked to be stopped during backup."
else
  CONTAINERS_TO_STOP_TOTAL="0"
  CONTAINERS_TOTAL="0"
  echo "Cannot access \"$DOCKER_SOCK\", won't look for containers to stop."
fi

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Stopping containers"
  docker stop $CONTAINERS_TO_STOP
fi

info "Creating backup"
BACKUP_FILENAME="$(date +"$BACKUP_FILENAME")"
tar -czvf "$BACKUP_FILENAME" $BACKUP_SOURCES # allow the var to expand, in case we have multiple sources

if [ ! -z "$GPG_PASSPHRASE" ]; then
  info "Encrypting backup"
  gpg --symmetric --cipher-algo aes256 --batch --passphrase "$GPG_PASSPHRASE" \
    -o "${BACKUP_FILENAME}.gpg" $BACKUP_FILENAME
  rm $BACKUP_FILENAME
  BACKUP_FILENAME="${BACKUP_FILENAME}.gpg"
fi

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Starting containers back up"
  docker start $CONTAINERS_TO_STOP
fi

if [ ! -z "$AWS_S3_BUCKET_NAME" ]; then
  info "Uploading backup to remote storage"
  echo "Will upload to bucket \"$AWS_S3_BUCKET_NAME\"."
  mc cp $MC_GLOBAL_OPTIONS "$BACKUP_FILENAME" "backup-target/$AWS_S3_BUCKET_NAME"
  echo "Upload finished."
fi

if [ -d "$BACKUP_ARCHIVE" ]; then
  info "Archiving backup"
  mv -v "$BACKUP_FILENAME" "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
fi

if [ -f "$BACKUP_FILENAME" ]; then
  info "Cleaning up"
  rm -vf "$BACKUP_FILENAME"
fi

info "Backup finished"
echo "Will wait for next scheduled backup."

if [ ! -z "$BACKUP_RETENTION_DAYS" ]; then
  info "Pruning old backups"
  echo "Sleeping ${BACKUP_PRUNING_LEEWAY} before checking eligibility."
  sleep "$BACKUP_PRUNING_LEEWAY"
  bucket=$AWS_S3_BUCKET_NAME

  rule_applies_to=$(
    mc rm $MC_GLOBAL_OPTIONS --fake --recursive -force \
      --older-than "${BACKUP_RETENTION_DAYS}d" \
      "backup-target/$bucket" \
      | wc -l
  )
  if [ "$rule_applies_to" == "0" ]; then
    echo "No backups found older than the configured retention period of $BACKUP_RETENTION_DAYS days."
    echo "Doing nothing."
    exit 0
  fi

  total=$(mc ls $MC_GLOBAL_OPTIONS "backup-target/$bucket" | wc -l)

  if [ "$rule_applies_to" == "$total" ]; then
    echo "Using a retention of ${BACKUP_RETENTION_DAYS} days would prune all currently existing backups, will not continue."
    echo "If this is what you want, please remove files manually instead of using this script."
    exit 1
  fi

  mc rm $MC_GLOBAL_OPTIONS \
    --recursive -force \
    --older-than "${BACKUP_RETENTION_DAYS}d" "backup-target/$bucket"
  echo "Successfully pruned ${rule_applies_to} backups older than ${BACKUP_RETENTION_DAYS} days."
fi


if [ ! -z "$BACKUP_ARCHIVE_RETENTION_DAYS" ]; then
  info "Pruning old backups in archive $BACKUP_ARCHIVE"
    mc rm -r --recursive -force \
      --older-than "${BACKUP_ARCHIVE_RETENTION_DAYS}d" \
      "$BACKUP_ARCHIVE" \
      | wc -l
fi