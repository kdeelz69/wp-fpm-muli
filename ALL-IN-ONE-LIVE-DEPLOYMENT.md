# Deploying an All-in-One WP Migration Backup to Production

This runbook describes how to deploy a WordPress website to the AWS production
server using this repository and an All-in-One WP Migration `.wpress` backup.

> **Important:** Import and test the backup in staging before production whenever
> possible. A backup may contain outdated or vulnerable plugins, unknown users,
> development credentials, malware, and development URLs.

## Required information

Obtain the following from the developer:

- The `.wpress` backup file
- The old development or staging URL
- A WordPress administrator login
- Required PHP version
- SMTP, API, payment gateway, and other integration details
- Premium plugin and theme licence details
- The backup creation date and expected file size
- Access to manage the production domain's DNS records

## 1. Validate the backup

Before importing it:

1. Confirm that the file extension is `.wpress`.
2. Compare its file size with the value supplied by the developer.
3. Scan the file with the company's approved malware scanner.
4. Import it into staging and test it before production when possible.
5. Check for unknown administrator accounts, abandoned plugins, and nulled or
   unlicensed themes/plugins.

If an existing production site will be replaced, create and verify a current
database and file backup before continuing.

## 2. Configure DNS

Create DNS records pointing the domain to the production server:

```text
A    example.com       13.213.40.226
A    www.example.com   13.213.40.226
```

If Cloudflare is used, it may be necessary to set the records to **DNS only**
temporarily while the first TLS certificate is issued.

Verify DNS:

```sh
nslookup example.com
nslookup www.example.com
```

Both names should resolve to `13.213.40.226` before certificate provisioning.

## 3. Connect to the server

Use an approved, current SSH key. Never use a private key that has been copied
into chat, email, documentation, or a ticket.

```sh
ssh -i NEW-KEY.pem ubuntu@13.213.40.226
sudo -i
```

Direct root SSH should be disabled after a named sudo account has been tested.

## 4. Update the deployment repository

```sh
cd /home/wp-fpm-multi_site
git status
git pull
```

Do not run `git pull` blindly if `git status` reports local changes. Review and
back up those changes first.

## 5. Create the production site

Start the guided deployment:

```sh
cd /home/wp-fpm-multi_site
sh deploy-site.sh
```

Choose:

```text
1) Add a new website or update an existing website
```

Example values:

```text
Site folder: customer-site
Compose project: customer_site
Apex domain: example.com
WWW domain: www.example.com
Primary domain: www.example.com
WordPress URL: https://www.example.com
WordPress version: the current company-approved version
PHP version: 8.3
```

Use unique, randomly generated passwords for:

- The WordPress administrator
- The site's database user
- The shared MariaDB root user

For the first site on the server, answer **Yes** when asked to set up the main
public web entry.

## 6. Verify the containers

Check the shared services:

```sh
cd /home/wp-fpm-multi_site/proxy
docker compose ps
```

Check the website services:

```sh
cd /home/wp-fpm-multi_site/sites/customer-site
docker compose -p customer_site ps
```

Expected services include:

- `shared_nginx_proxy`
- `shared_acme_companion`
- `shared_mariadb`
- The site's WordPress/PHP-FPM container
- The site's Nginx container

Review website logs:

```sh
docker compose -p customer_site logs --tail=100 wordpress nginx
```

Resolve container startup or database connection errors before continuing.

## 7. Verify the TLS certificate

Review certificate provisioning logs:

```sh
cd /home/wp-fpm-multi_site/proxy
docker compose logs --tail=200 acme-companion
```

Inspect the issued certificate:

```sh
openssl s_client \
  -connect example.com:443 \
  -servername example.com </dev/null 2>/dev/null |
openssl x509 -noout -subject -issuer -dates
```

Verify both domain variants in a browser:

```text
https://example.com
https://www.example.com
```

## 8. Prepare the import directory

Run the deployment menu again:

```sh
cd /home/wp-fpm-multi_site
sh deploy-site.sh
```

Choose:

```text
5) Fix WordPress upload/import permissions
```

Provide the site folder and Compose project name:

```text
customer-site
customer_site
```

## 9. Upload the `.wpress` backup

From the local workstation:

```sh
scp -i NEW-KEY.pem website-name.wpress \
  ubuntu@13.213.40.226:/tmp/
```

On the server, move the file into the site's protected backup directory:

```sh
sudo mv /tmp/website-name.wpress \
  /home/wp-fpm-multi_site/sites/customer-site/html/wp-content/ai1wm-backups/
```

Run menu option 5 again to correct ownership and permissions:

```sh
cd /home/wp-fpm-multi_site
sh deploy-site.sh
```

The Nginx production template blocks public web access to
`wp-content/ai1wm-backups`.

## 10. Restore the backup

Open the WordPress dashboard:

```text
https://www.example.com/wp-admin
```

Use one of these All-in-One WP Migration workflows:

```text
All-in-One WP Migration → Backups → Select the uploaded backup → Restore
```

or:

```text
All-in-One WP Migration → Import → File
```

The restored database may replace the temporary production administrator with
the administrator accounts contained in the backup. Use the developer-provided
login if WordPress requests authentication again.

## 11. Replace development URLs

Assume:

```text
Old URL:  https://dev.example.com
Live URL: https://www.example.com
```

Run a dry run first:

```sh
cd /home/wp-fpm-multi_site/sites/customer-site

docker compose -p customer_site run --rm -T wpcli \
  wp search-replace \
  'https://dev.example.com' \
  'https://www.example.com' \
  --all-tables \
  --skip-columns=guid \
  --dry-run \
  --path=/var/www/html
```

Review the output, then run the actual replacement:

```sh
docker compose -p customer_site run --rm -T wpcli \
  wp search-replace \
  'https://dev.example.com' \
  'https://www.example.com' \
  --all-tables \
  --skip-columns=guid \
  --path=/var/www/html
```

Set the canonical WordPress URLs and clear the cache:

```sh
docker compose -p customer_site run --rm -T wpcli \
  wp option update home 'https://www.example.com' \
  --path=/var/www/html

docker compose -p customer_site run --rm -T wpcli \
  wp option update siteurl 'https://www.example.com' \
  --path=/var/www/html

docker compose -p customer_site run --rm -T wpcli \
  wp cache flush \
  --path=/var/www/html
```

WP-CLI correctly handles serialized WordPress data. Do not perform a raw SQL
string replacement for URLs.

## 12. Reapply the production security baseline

An All-in-One restore can replace database settings, users, plugins, themes, and
possibly `wp-config.php`. Reapply the hardening after every restore:

```sh
cd /home/wp-fpm-multi_site
sh deploy-site.sh
```

Choose option 5 again:

```text
5) Fix WordPress upload/import permissions
```

This operation:

- Normalizes required writable directories
- Restricts `wp-config.php`
- Disables the built-in theme/plugin file editor
- Forces SSL for WordPress administration
- Disables production debug output

## 13. Update and clean WordPress

Review core, plugin, and theme updates:

```sh
cd /home/wp-fpm-multi_site/sites/customer-site

docker compose -p customer_site run --rm -T wpcli \
  wp core check-update --path=/var/www/html

docker compose -p customer_site run --rm -T wpcli \
  wp plugin list --path=/var/www/html

docker compose -p customer_site run --rm -T wpcli \
  wp theme list --path=/var/www/html
```

Before production approval:

1. Update WordPress core, active plugins, and active themes in staging first.
2. Delete unused plugins and themes rather than only deactivating them.
3. Remove unknown or unnecessary administrator accounts.
4. Avoid predictable administrator names such as `admin` or `administrator`.
5. Rotate administrator, database, SMTP, API, and payment credentials.
6. Replace development integration settings with production settings.
7. Verify premium plugin and theme licences.
8. Confirm that production `WP_DEBUG` is disabled.

Do not update everything blindly on production. Test updates in staging and take
a backup before applying them to the live site.

## 14. Run the repository security audit

```sh
cd /home/wp-fpm-multi_site
sh security-audit.sh
```

Production approval requires:

```text
FAIL = 0
```

Every `WARN` must be investigated and documented. The script does not replace an
external authenticated vulnerability assessment.

## 15. Perform functional testing

Test at least the following:

- Homepage and internal pages
- Mobile and desktop layouts
- WordPress login and logout
- Password reset
- Contact forms and email delivery
- Search
- Media and document uploads
- Checkout and payment gateway in the approved test mode
- User registration, if enabled
- Scheduled jobs and WP-Cron
- Redirects and custom 404 pages
- Browser console errors
- HTTP-to-HTTPS redirection
- Canonical `www` or non-`www` redirection
- SMTP, CRM, analytics, CAPTCHA, maps, and other external integrations

## 16. Remove the server-side migration backup

After the restore has been validated and an approved off-server copy exists,
verify the exact path and remove the production server copy:

```sh
rm /home/wp-fpm-multi_site/sites/customer-site/html/wp-content/ai1wm-backups/website-name.wpress
```

Do not use wildcards. Confirm the exact site folder and filename before deleting
anything.

## 17. Complete the go-live checks

Confirm all of the following before production approval:

- AWS Security Group exposes only ports 80 and 443 publicly.
- SSH port 22 is restricted to the company VPN or fixed administrator IPs.
- MariaDB port 3306 is not publicly accessible.
- Any SSH key shared through chat, email, or a ticket has been revoked.
- TLS certificates are valid for all production hostnames.
- HTTP redirects to HTTPS.
- Backups are encrypted, automated, stored outside the EC2 instance, and tested.
- Monitoring covers disk space, certificate expiry, container restarts, 5xx
  responses, and authentication failures.
- `security-audit.sh` reports zero failures.
- An external port/TLS/header scan is complete.
- An authenticated WordPress vulnerability assessment is complete.
- The business owner has approved the functional test results.

## Mandatory rule after every restore

After every All-in-One WP Migration restore, always repeat these actions:

1. Replace development URLs safely with WP-CLI.
2. Rotate imported credentials.
3. Update and remove vulnerable or unused components.
4. Run deployment menu option 5 to reapply permissions and production constants.
5. Run `security-audit.sh` and resolve every failure.
6. Complete functional and external vulnerability testing before go-live.
