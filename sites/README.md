# Sites

Use the root [`README.md`](../README.md) for the full step-by-step deployment
commands.

Each production website should be copied from `sites/site-template/` and run
with a unique Compose project name. The shared MariaDB container lives in
`proxy/`; each website gets its own database and database user inside it.

```bash
sh deploy-site.sh
sh deploy-site.sh site-one site_one --start-proxy
sh deploy-site.sh site-two site_two
```
