#!/bin/bash
exec rspamc -h "$(cat /run/secrets/rspamd_connection)" -P "$(cat /run/secrets/rspamd_password)" learn_spam
