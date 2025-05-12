#!/bin/bash
set -e

# Parse hostname argument or prompt
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

echo "Setting hostname in Postfix..."
postconf -e "myhostname = $SERVER_HOSTNAME"
postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"

echo "Ensuring STARTTLS settings..."
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"
postconf -e "smtpd_tls_auth_only = yes"
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
postconf -e "smtpd_tls_loglevel = 1"

echo "Configuring Dovecot auth mechanisms..."
sed -i 's/^auth_mechanisms = .*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf

echo "Updating protocol support (IMAP, POP3, LMTP)..."
sed -i '/^#\?protocols =/c\protocols = imap pop3 lmtp' /etc/dovecot/dovecot.conf

echo "Overwriting 10-master.conf with correct listener config..."
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

echo "Appending secure SSL settings to 10-ssl.conf..."
SSL_CONF="/etc/dovecot/conf.d/10-ssl.conf"
grep -q 'ssl = required' "$SSL_CONF" || cat <<'EOT' >> "$SSL_CONF"

ssl = required
ssl_cert = </etc/letsencrypt/live/mail.greediersocialmedia.co.uk/fullchain.pem
ssl_key = </etc/letsencrypt/live/mail.greediersocialmedia.co.uk/privkey.pem
ssl_min_protocol = TLSv1.2
ssl_cipher_list = HIGH:!aNULL:!MD5
ssl_prefer_server_ciphers = yes
ssl_dh = </usr/share/dovecot/dh.pem
ssl_client_ca_dir = /etc/ssl/certs
EOT

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

echo "Fixing permissions..."
chown root:root "$SNI_CONF"
chmod 644 "$SNI_CONF"

echo "Restarting mail services..."
systemctl restart postfix dovecot

echo "✅ Mail server setup complete. Server ready for multi-domain Outlook & Gmail compatibility."
