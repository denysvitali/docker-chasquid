FROM golang:alpine AS chasquid
RUN apk add --no-cache git wget make
WORKDIR /app
RUN git clone https://blitiri.com.ar/repos/chasquid && \
    cd chasquid && \
    make

FROM golang:alpine AS dkim
RUN apk add --no-cache git wget make
WORKDIR /app
RUN git clone https://github.com/denysvitali/dkim .
RUN make && mv dkim* /

FROM golang:alpine AS chasquid-rspamd
RUN apk add --no-cache git
RUN go install github.com/thor77/chasquid-rspamd@0.1.1

# --- Main Container ----
FROM alpine:3.12
ARG ALIAS_RESOLVE_VERSION=0.0.4
RUN apk add --no-cache bash \
    supervisor \
    shadow \
    dovecot \
    dovecot-mysql \
    dovecot-pigeonhole-plugin \
    milter-greylist \
    clamav \
    clamav-db \
    clamav-libunrar \
    clamav-milter \
    mysql-client \
    sudo \
    wget
COPY --from=chasquid /app/chasquid /usr/bin/chasquid
COPY --from=dkim /dkimkeygen /usr/bin/dkimkeygen
COPY --from=dkim /dkimsign /usr/bin/dkimsign
COPY --from=dkim /dkimverify /usr/bin/dkimverify
COPY --from=chasquid-rspamd /go/bin/chasquid-rspamd /usr/bin/chasquid-rspamd
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
RUN wget -O /usr/local/bin/chasquid-alias-resolve \
      "https://github.com/denysvitali/chasquid-alias/releases/download/$ALIAS_RESOLVE_VERSION/alias-resolve" && \
    chmod a+x /usr/local/bin/chasquid-alias-resolve && \
    ln -s /usr/local/bin/chasquid-alias-resolve /etc/chasquid/hooks/alias-exists && \
    ln -s /usr/local/bin/chasquid-alias-resolve /etc/chasquid/hooks/alias-resolve
ENTRYPOINT /entrypoint.sh
