#!/bin/sh

CHASQUID_FILE="/var/run/dovecot/auth-chasquid-client"

echo "Waiting for Dovecot's Chasquid socket"
while [ ! -S "$CHASQUID_FILE" ]; do
  printf "."
  sleep 1
done
echo "Dovecot's Chasquid socket available, starting Chasquid"

/usr/local/bin/chasquid.sh
