FROM golang:alpine AS chasquid
RUN apk add --no-cache git wget make
RUN mkdir -p /go/src/blitiri.com.ar/repos/chasquid
WORKDIR /go/src/blitiri.com.ar/repos/chasquid
ENV GOPATH=/go
RUN git clone https://github.com/denysvitali/chasquid .
RUN make

FROM golang:alpine AS dkim
RUN apk add --no-cache git wget make
RUN mkdir -p /go/src/github.com/driusan/dkim
WORKDIR /go/src/github.com/driusan/dkim/
ENV GOPATH=/go
RUN git clone https://github.com/denysvitali/dkim .
RUN make && mv dkim* /

FROM alpine:3.11
RUN apk add --no-cache bash \
    supervisor \
    shadow \
    dovecot \
    dovecot-mysql \
    dovecot-pigeonhole-plugin \
    milter-greylist \
    rspamd-client \
    clamav \
    clamav-db \
    clamav-libunrar \
    clamav-milter \
    mysql-client \
    sudo
COPY --from=chasquid /go/src/blitiri.com.ar/repos/chasquid/chasquid /usr/bin/chasquid
COPY --from=dkim /dkimkeygen /usr/bin/dkimkeygen
COPY --from=dkim /dkimsign /usr/bin/dkimsign
COPY --from=dkim /dkimverify /usr/bin/dkimverify
RUN adduser -D mail-server
RUN usermod -a -G tty mail-server
RUN adduser -D vmail
RUN mkdir -p /srv/mail/mailboxes && chown vmail:vmail /srv/mail/mailboxes
COPY ./vars.sh /
COPY ./init_chasquid.sh /usr/local/bin/init_chasquid.sh
COPY ./scripts/ /usr/local/bin/
COPY ./entrypoint.sh /
COPY supervisord.conf /etc/supervisord.conf
COPY ./dovecot/conf.d/ /etc/dovecot/conf.d/
COPY ./dovecot/sieve/ /etc/dovecot/sieve
COPY ./chasquid/hooks/ /etc/chasquid/hooks
ENTRYPOINT /entrypoint.sh
