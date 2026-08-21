# Production security baseline

This repository reduces common WordPress, PHP, Nginx, database, and container
risks. It does not guarantee that an imported theme, plugin, database, or custom
code is vulnerability-free. A site must pass the checks below before production.

## Before every launch

1. Import the backup only from an approved source and scan it for malware.
2. Update WordPress core, active plugins, and active themes in staging. Remove
   inactive or abandoned plugins/themes rather than merely disabling them.
3. Rotate WordPress administrator, database, SMTP, API, and backup credentials.
   Never reuse credentials from the developer environment.
4. Run `sh deploy-site.sh`, then option 5 to normalize writable directories and
   protect `wp-config.php`.
5. Run `sh security-audit.sh`. A production release must have zero `FAIL` lines;
   every `WARN` requires a documented review.
6. Test login, forms, email, checkout, scheduled jobs, backups, and restore in
   staging before changing DNS.

## AWS host controls

- Allow inbound 80/443 globally. Allow SSH 22 only from a company VPN or fixed
  administrator IP; never from `0.0.0.0/0` or `::/0`.
- Use a named sudo account and disable direct root SSH after testing it. Keep SSH
  password authentication disabled. Rotate any key copied into chat or tickets.
- Enable UFW with Docker-aware rules, automatic security updates, Fail2ban or an
  equivalent SSH control, CloudWatch alerts, and encrypted EBS snapshots.
- Keep MariaDB bound to `127.0.0.1`; never publish port 3306 publicly.
- Configure Docker log rotation and monitor disk, certificate expiry, container
  restarts, 5xx responses, and authentication failures.

## WordPress controls after importing a backup

Add these values to `wp-config.php` after confirming the site does not need the
built-in editor. Do not set `DISALLOW_FILE_MODS` unless updates are performed by
an external release pipeline.

```php
define('DISALLOW_FILE_EDIT', true);
define('FORCE_SSL_ADMIN', true);
define('WP_DEBUG', false);
define('WP_DEBUG_DISPLAY', false);
```

XML-RPC is denied by the default Nginx template. Remove that location only if a
documented integration requires XML-RPC, then protect it with rate limiting or an
allowlist. The template also blocks backup folders, dotfiles, SQL/log/config
artifacts, PHP execution in uploads, and nonexistent PHP script forwarding.

## Recurring maintenance

- Weekly: review updates and vulnerability advisories; patch in staging first.
- Daily: automated encrypted database and file backups, stored outside this EC2
  instance, with retention and restore testing.
- Quarterly: remove unused accounts/keys, review AWS Security Groups and IAM,
  rotate privileged credentials, and run an authenticated VA scan.
- After every import or release: rerun `security-audit.sh` and an external TLS,
  header, port, and WordPress vulnerability scan.
