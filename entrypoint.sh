#!/bin/bash
set -e

CHASQUID_CONFIG_FILE=${CHASQUID_CONFIG_FILE:-"/etc/chasquid/chasquid.conf"}

CSQ_HOSTNAME=${CSQ_HOSTNAME:-"localhost"}
CSQ_DOMAINS=${CSQ_DOMAINS:-"localhost"} # Multiple values, comma separated
CSQ_MAX_DATA_SIZE_MB=${CSQ_MAX_DATA_SIZE_MB:-50}
CSQ_SMTP_ADDRESS=${CSQ_SMTP_ADDRESS:-0.0.0.0:25} # Multiple values, comma separated
CSQ_SUBMISSION_ADDRESS=${CSQ_SUBMISSION_ADDRESS:-0.0.0.0:587} # Multiple values, comma separated
CSQ_SUBMISSION_TLS_ADDRESS=${CSQ_SUBMISSION_TLS_ADDRESS:-0.0.0.0:465} # Multiple values, comma separated
CSQ_MONITORING_ADDRESS=${CSQ_MONITORING_ADDRESS:-127.0.0.1:8080}
CSQ_MAIL_DELIVERY_AGENT_BIN=${CSQ_MAIL_DELIVERY_AGENT_BIN:-maildrop}
CSQ_MAIL_DELIVERY_AGENT_ARGS=${CSQ_MAIL_DELIVERY_AGENT_ARGS:--f,%from%,-d,%to_user%}
CSQ_DATA_DIR=${CSQ_DATA_DIR:-/var/lib/chasquid}
CSQ_SUFFIX_SEPARATORS=${CSQ_SUFFIX_SEPARATORS:-+}
CSQ_DROP_CHARACTERS=${CSQ_DROP_CHARACTERS:-.}
CSQ_MAIL_LOG_PATH=${CSQ_MAIL_LOG_PATH:-<stdout>}
CSQ_DOVECOT_AUTH=${CSQ_DOVECOT_AUTH:-false}
CSQ_ARGS=${CSQ_ARGS:-logtime}


# Dovecot Vars
DOVECOT_DB_HOST=${DOVECOT_DB_HOST:-127.0.0.1}
DOVECOT_DB_NAME=${DOVECOT_DB_NAME:-mail}
DOVECOT_DB_USER=${DOVECOT_DB_USER:-dovecot}
DOVECOT_DB_PASSWORD=${DOVECOT_DB_PASSWORD:-password}

mkdir -p "$(dirname "$CHASQUID_CONFIG_FILE")/certs"
mkdir -p "$(dirname "$CHASQUID_CONFIG_FILE")/domains/${CSQ_HOSTNAME}"

# Create domains directories
IFS=',' read -r -a CSQ_DOMAINS_ENTRIES <<< "$CSQ_DOMAINS"
for domain in "${CSQ_DOMAINS_ENTRIES[@]}"; do
  mkdir -p "$(dirname "$CHASQUID_CONFIG_FILE")/domains/${domain}"
  mkdir -p "$(dirname "$CHASQUID_CONFIG_FILE")/certs/${domain}"

  if [ ! -f "$(dirname "$CHASQUID_CONFIG_FILE")/certs/${domain}/private.pem" ]; then
    pushd "$(dirname "$CHASQUID_CONFIG_FILE")/certs/${domain}/"
    echo "Generating DKIM key for ${domain}..."
    dkimkeygen
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


echo "********************"
echo "* Starting CHASQUID *"
echo "********************"


printf "%s\n%s\nchasquid -v 1 -config_dir \"%s\" %s" "#!/bin/sh" "sleep 5" "$(dirname "$CHASQUID_CONFIG_FILE")" "$CSQ_ARGS" > /usr/local/bin/chasquid.sh
chmod 755 /usr/local/bin/chasquid.sh

supervisord -n
