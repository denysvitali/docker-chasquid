#!/bin/sh

while true; do
  M_TIMEOUT=$((60 * 60 * 12)) # Every 12 hours
  sleep "$M_TIMEOUT"
  sudo -u clamav freshclam
done
