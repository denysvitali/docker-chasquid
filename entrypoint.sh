#!/bin/bash
set -e
source ./vars.sh

mkdir -p "$CHASQUID_CONFIG_DIR/certs"
mkdir -p "$CHASQUID_CONFIG_DIR/domains/${CSQ_HOSTNAME}"

# Get domains from MySQL
DOMAIN_LIST=$(echo "SELECT domain FROM domains" | mysql --user "$DOVECOT_DB_USER" -h "$DOVECOT_DB_HOST" --password="$DOVECOT_DB_PASSWORD" "$DOVECOT_DB_NAME" | tail -n +2 | xargs)

echo "Domain list: $DOMAIN_LIST"

# Create domains dirs

for domain in $DOMAIN_LIST; do
  echo "=> $domain"
  mkdir -p "$CHASQUID_CONFIG_DIR/domains/${domain}"
  mkdir -p "$CHASQUID_CONFIG_DIR/certs/${domain}"

  if [ ! -f "$CHASQUID_CONFIG_DIR/certs/${domain}/private.pem" ]; then
    pushd "$(dirname "$CHASQUID_CONFIG_FILE")/certs/${domain}/"
    echo "Generating DKIM key for ${domain}..."
    dkimkeygen -a "$DKIM_ALGORITHM" -d dns.txt -o private.pem
    popd
  fi

  if [ ! -f "$CHASQUID_CONFIG_DIR/certs/${domain}/private-second.pem" ]; then
    pushd "$(dirname "$CHASQUID_CONFIG_FILE")/certs/${domain}/"
    echo "Generating secondary DKIM key ($DKIM_SECOND_ALGORITHM) for ${domain}..."
    dkimkeygen -a "$DKIM_SECOND_ALGORITHM" -d dns-second.txt -o private-second.pem
    popd
  fi

  if [ ! -f "$CHASQUID_CONFIG_DIR/domains/${domain}/dkim_selector" ]; then
    pushd "$CHASQUID_CONFIG_DIR/domains/${domain}/"
    echo "$DKIM_SELECTOR" > dkim_selector 
    popd
  fi

  if [ ! -f "$CHASQUID_CONFIG_DIR/domains/${domain}/dkim_selector_second" ]; then
    pushd "$CHASQUID_CONFIG_DIR/domains/${domain}/"
    echo "$DKIM_SECOND_SELECTOR" > dkim_selector_second
    popd
  fi
done

touch "$CHASQUID_CONFIG_FILE"

if [ -d "$CSQ_DATA_DIR" ]; then
  mkdir -p "$CSQ_DATA_DIR";
fi

function csqc(){
  key=$1
  value=$2
  echo "$key: $value" >> "$CHASQUID_CONFIG_FILE"
}

function csqc_b(){
  csqc "$1" "$2"
}

function csqc_s(){
  csqc "$1" "\"$2\""
}

function csqc_a(){
  key=$1
  value=$2
  IFS=',' read -r -a MULTIPLE_VALUES <<< "$value"
  for single_value in "${MULTIPLE_VALUES[@]}"; do
    csqc_s "$key" "$single_value"
  done
}

csqc_s "hostname" "$CSQ_HOSTNAME"
csqc "max_data_size_mb" "$CSQ_MAX_DATA_SIZE_MB"

csqc_a "smtp_address" "$CSQ_SMTP_ADDRESS"
csqc_a "submission_address" "$CSQ_SUBMISSION_ADDRESS"
csqc_a "submission_over_tls_address" "$CSQ_SUBMISSION_TLS_ADDRESS"

csqc_s "monitoring_address" "$CSQ_MONITORING_ADDRESS"

csqc_s "mail_delivery_agent_bin" "$CSQ_MAIL_DELIVERY_AGENT_BIN"
csqc_a "mail_delivery_agent_args" "$CSQ_MAIL_DELIVERY_AGENT_ARGS"

csqc_s "data_dir" "$CSQ_DATA_DIR"
csqc_s "suffix_separators" "$CSQ_SUFFIX_SEPARATORS"
csqc_s "drop_characters" "$CSQ_DROP_CHARACTERS"

csqc_s "mail_log_path" "${CSQ_MAIL_LOG_PATH}"
csqc_b "dovecot_auth" "${CSQ_DOVECOT_AUTH}"
csqc_b "haproxy_incoming" "${CSQ_HAPROXY_INCOMING}"

echo "Chasquid Config:"
cat "$CHASQUID_CONFIG_FILE"

######################
#    Setup Dovecot   #
######################
cat << EOF > /etc/dovecot/conf.d/auth-sql.conf.ext
passdb {
    driver = sql
    args = /etc/dovecot/dovecot-sql.conf
}

userdb {
    driver = sql
    args = /etc/dovecot/dovecot-sql.conf
}
EOF

cat << EOF >> /etc/dovecot/dovecot-sql.conf
driver = mysql
connect = "host=$DOVECOT_DB_HOST dbname=$DOVECOT_DB_NAME user=$DOVECOT_DB_USER password=$DOVECOT_DB_PASSWORD"
default_pass_scheme = BLF-CRYPT

password_query = SELECT mailboxes.local_part AS username, domains.domain, mailboxes.password FROM mailboxes INNER JOIN domains ON mailboxes.domain_id = domains.id WHERE mailboxes.local_part = '%n' AND domains.domain = '%d' AND domains.active = 1 AND mailboxes.active = 1;
user_query = SELECT mailboxes.homedir AS home, mailboxes.maildir AS mail, CONCAT('*:storage=', COALESCE(mailboxes.quota, domains.quota, 0), 'G') AS quota_rule FROM mailboxes INNER JOIN domains ON mailboxes.domain_id = domains.id WHERE mailboxes.local_part = '%n' AND domains.domain = '%d' AND domains.active = 1 AND mailboxes.active = 1 AND mailboxes.send_only = 0;
iterate_query = SELECT mailboxes.local_part AS username, domains.domain FROM mailboxes INNER JOIN domains ON mailboxes.domain_id = domains.id WHERE mailboxes.local_part = '%n' AND domains.domain = '%d' AND domains.active = 1 AND mailboxes.active = 1 AND mailboxes.send_only = 0;
EOF


cat << EOF >> /etc/dovecot/conf.d/10-ssl.conf
ssl = yes
# Preferred permissions: root:root 0444
ssl_cert = </etc/chasquid/certs/$CSQ_HOSTNAME/fullchain.pem
# Preferred permissions: root:root 0400
ssl_key = </etc/chasquid/certs/$CSQ_HOSTNAME/privkey.pem
EOF

echo "Dovecot conf:"
cat /etc/dovecot/dovecot.conf

echo "dovecot-sql.conf:"
cat /etc/dovecot/dovecot-sql.conf


# Compile sieves:
sievec /etc/dovecot/sieve/


echo "********************"
echo "* Starting CHASQUID *"
echo "********************"


printf "%s\n%s\nchasquid -v 1 -config_dir \"%s\" %s" "#!/bin/sh" "sleep 5" "$(dirname "$CHASQUID_CONFIG_FILE")" "$CSQ_ARGS" > /usr/local/bin/chasquid.sh
chmod 755 /usr/local/bin/chasquid.sh

echo -n "$RSPAMD_CONNECTION" > /run/secrets/rspamd_connection
echo -n "$RSPAMD_PASSWORD" > /run/secrets/rspamd_password

mkdir -p /run/clamav
chown clamav:clamav /run/clamav
freshclam -u clamav
supervisord -n
