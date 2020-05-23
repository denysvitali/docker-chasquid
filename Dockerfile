FROM golang:alpine AS builder
RUN apk add --no-cache git wget make
RUN mkdir -p /go/src/blitiri.com.ar/repos/chasquid
WORKDIR /go/src/blitiri.com.ar/repos/chasquid
ENV GOPATH=/go
RUN git clone https://github.com/denysvitali/chasquid .
RUN make

FROM alpine:3.11
RUN apk add --no-cache bash dovecot supervisor shadow dovecot-mysql
COPY --from=builder /go/src/blitiri.com.ar/repos/chasquid/chasquid /usr/bin/chasquid
RUN adduser -D mail-server
RUN usermod -a -G tty mail-server
COPY ./entrypoint.sh /
COPY supervisord.conf /etc/supervisord.conf
COPY ./dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/
ENTRYPOINT /entrypoint.sh
