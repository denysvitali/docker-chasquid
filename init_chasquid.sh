#!/bin/sh

CHASQUID_FILE="/var/run/dovecot/auth-chasquid-client"
CLAMAV_SOCKET="/run/clamav/clamd.sock"

echo "Waiting for Dovecot's Chasquid socket"
while [ ! -S "$CHASQUID_FILE" ]; do
  printf "."
  sleep 1
done

echo "Waiting for ClamAV socket"
while [ ! -S "$CLAMAV_SOCKET" ]; do
  printf "."
  sleep 1
done

echo "Dovecot's Chasquid socket available, ClamAV ready, starting Chasquid"

/usr/local/bin/chasquid.sh
