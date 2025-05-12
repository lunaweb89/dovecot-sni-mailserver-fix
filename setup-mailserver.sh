#!/bin/bash
set -e

# Prompt for hostname if not supplied via --hostname
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --hostname) SERVER_HOSTNAME="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$SERVER_HOSTNAME" ]; then
    if [ -t 0 ]; then
        read -rp "Enter the server hostname (e.g., s01.lunaservers.xyz): " SERVER_HOSTNAME
    else
        SERVER_HOSTNAME=$(sudo /usr/bin/env bash -c 'read -rp "Enter the server hostname (e.g., s01.lunaservers.xyz): " input && echo "$input"')
    fi
fi

echo "Installing dovecot-lmtpd package for LMTP support..."
apt update
apt install -y dovecot-lmtpd

echo "Setting hostname in Postfix..."
postconf -e "myhostname = $SERVER_HOSTNAME"

echo "Ensuring STARTTLS settings..."
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"
postconf -e "smtpd_tls_auth_only = yes"
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
postconf -e "smtpd_tls_loglevel = 1"

echo "Configuring Dovecot auth mechanisms..."
sed -i 's/^auth_mechanisms = .*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf

echo "Enabling IMAPS, POP3S, and LMTP protocols..."
sed -i '/^#\?protocols =/c\protocols = imap pop3 lmtp' /etc/dovecot/dovecot.conf

echo "Overwriting Dovecot imap-login + lmtp listener block..."
cat <<EOF > /etc/dovecot/conf.d/10-master.conf
service imap-login {
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
EOF

echo "Generating Dovecot SNI configuration..."
SNI_CONF="/etc/dovecot/conf.d/10-ssl-sni.conf"
echo "# Auto-generated SNI mapping" > "$SNI_CONF"

for domain_path in /etc/letsencrypt/live/*/; do
    domain=$(basename "$domain_path")
    if [[ "$domain" == "README" ]]; then continue; fi
    if [[ -f "$domain_path/fullchain.pem" && -f "$domain_path/privkey.pem" ]]; then
        echo "local_name $domain {" >> "$SNI_CONF"
        echo "  ssl_cert = </etc/letsencrypt/live/$domain/fullchain.pem" >> "$SNI_CONF"
        echo "  ssl_key  = </etc/letsencrypt/live/$domain/privkey.pem" >> "$SNI_CONF"
        echo "}" >> "$SNI_CONF"
        echo "" >> "$SNI_CONF"
    fi
done

echo "Finalizing permissions..."
chown root:root "$SNI_CONF"
chmod 644 "$SNI_CONF"

echo "Restarting services..."
systemctl restart postfix dovecot

echo "✅ Mail server setup complete. Server ready for multi-domain Outlook & Gmail compatibility."
