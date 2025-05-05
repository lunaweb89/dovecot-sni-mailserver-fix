# Dovecot + Postfix Mail Server Fix Script

This script automatically configures a mail server to:
- Set the correct `myhostname` in Postfix.
- Enable and configure SSL/TLS with support for Outlook and Gmail.
- Detect hosted domains and configure Dovecot SNI (Server Name Indication) per domain SSL.
- Apply STARTTLS and submission fixes for smooth SMTP communication.

## Usage

Run the setup script as root:

```bash
bash setup-mailserver.sh --hostname your.server.hostname
```

## Requirements

- Let's Encrypt certificates issued per domain (must exist under `/etc/letsencrypt/live`)
- Postfix and Dovecot pre-installed

