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
RUN git clone https://github.com/driusan/dkim .
RUN go build -o /dkimkeygen cmd/dkimkeygen/main.go 
RUN go build -o /dkimsign cmd/dkimsign/main.go
RUN go build -o /dkimverify cmd/dkimverify/main.go

FROM alpine:3.11
RUN apk add --no-cache bash dovecot supervisor shadow dovecot-mysql milter-greylist rspamd clamav
COPY --from=chasquid /go/src/blitiri.com.ar/repos/chasquid/chasquid /usr/bin/chasquid
COPY --from=dkim /dkimkeygen /usr/bin/dkimkeygen
COPY --from=dkim /dkimsign /usr/bin/dkimsign
COPY --from=dkim /dkimverify /usr/bin/dkimverify
RUN adduser -D mail-server
RUN usermod -a -G tty mail-server
RUN adduser -D vmail
RUN mkdir -p /srv/mail/mailboxes && chown vmail:vmail /srv/mail/mailboxes
COPY ./init_chasquid.sh /usr/local/bin/init_chasquid.sh
COPY ./entrypoint.sh /
COPY supervisord.conf /etc/supervisord.conf
COPY ./dovecot/conf.d/ /etc/dovecot/conf.d/
COPY ./chasquid/hooks/ /etc/chasquid/hooks
ENTRYPOINT /entrypoint.sh
