# Copyright 2021 - Igor VISI < igorvisi.com >
# SPDX-License-Identifier: MPL-2.0
# Most of line are taken from github.com/offen/docker-volume-backup

FROM golang:1.16-alpine as builder
ARG MC_VERSION=RELEASE.2021-07-27T06-46-19Z
RUN go install -ldflags "-X github.com/minio/mc/cmd.ReleaseTag=$MC_VERSION" github.com/minio/mc@$MC_VERSION


FROM alpine:3.14

WORKDIR /root

RUN apk add --update ca-certificates docker openrc gnupg
RUN update-ca-certificates
RUN rc-update add docker boot

COPY --from=builder /go/bin/mc /usr/bin/mc
RUN mc --version

COPY src/backup.sh src/entrypoint.sh /root/
RUN chmod +x backup.sh && mv backup.sh /usr/bin/backup \
  && chmod +x entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]
