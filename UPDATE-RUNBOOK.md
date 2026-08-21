# Safe WordPress, PHP, Nginx, Plugin, and Theme Updates

Use `update-site.sh` for controlled maintenance. It performs preflight checks,
creates an off-web rollback backup, enables maintenance mode, updates components
one at a time, runs health checks, and rolls back detected failures.

No script can guarantee plugin/theme compatibility. Custom business flows must
still be tested in staging and then checked manually after production updates.

## Required release process

1. Confirm that automated off-instance backups are healthy.
2. Restore the latest production backup into staging.
3. Run check mode against staging.
4. Apply and functionally test the update in staging.
5. Schedule a production maintenance window.
6. Run check mode against production.
7. Apply only the versions approved in staging.
8. Run `security-audit.sh`, WPScan, ZAP Baseline, and manual smoke tests.

## Check without changing the site

```sh
cd /home/wp-fpm-multi_site
sh update-site.sh check customer-site customer_site
```

Check a proposed PHP and WordPress runtime:

```sh
sh update-site.sh check customer-site customer_site \
  --php 8.4 \
  --wordpress 6.9.4
```

This pulls the proposed WordPress/PHP image and syntax-checks PHP files under
plugins and themes. It does not prove behavioral compatibility, so staging is
still mandatory for PHP minor/major upgrades.

## Apply approved updates

Update WordPress core, plugins, and themes while retaining current containers:

```sh
sh update-site.sh apply customer-site customer_site
```

Also refresh the configured WordPress, WP-CLI, and Nginx images:

```sh
sh update-site.sh apply customer-site customer_site --refresh-images
```

Apply PHP and WordPress versions already approved in staging:

```sh
sh update-site.sh apply customer-site customer_site \
  --php 8.4 \
  --wordpress 6.9.4 \
  --refresh-images
```

Skip a component class when required:

```sh
sh update-site.sh apply customer-site customer_site \
  --skip-plugins \
  --skip-themes
```

## Backup and rollback behavior

Backups are stored outside the site's web root:

```text
/home/wp-fpm-multi_site/update-backups/<site>/<UTC timestamp>/
```

Each update stores:

- A database export
- WordPress core, plugins, themes, and configuration files
- The site's `.env`
- The site's Compose file
- Local rollback tags for the exact WordPress, WP-CLI, and Nginx images

Uploads, caches, and All-in-One migration archives are excluded because the
updater does not modify them. If an update or health check fails, the script
restores the database, code, and previous runtime versions automatically.

Keep the rollback backup until the client has approved the updated production
site. Copy long-term backups to encrypted off-instance storage.

## Tests required after a successful update

```sh
cd /home/wp-fpm-multi_site
sh security-audit.sh
```

Then manually test login, forms, email, checkout/payment, search, uploads,
scheduled jobs, integrations, redirects, and browser console errors. Run WPScan
and ZAP Baseline externally. Do not approve production with unresolved failures
or high-risk findings.
