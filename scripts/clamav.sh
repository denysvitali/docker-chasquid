#!/bin/sh

sudo chown -R clamav:clamav /run/clamav/
sudo chown -R clamav:clamav /var/lib/clamav
sudo -u clamav freshclam
sudo -u clamav clamd --foreground
