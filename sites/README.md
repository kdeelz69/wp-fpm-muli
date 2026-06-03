# Sites

Use the root [`README.md`](../README.md) for the full step-by-step deployment
commands.

Each production site should be copied from `sites/site-template/` and run with a
unique Compose project name:

```bash
sh deploy-site.sh site-one site_one --start-proxy
sh deploy-site.sh site-two site_two
```
