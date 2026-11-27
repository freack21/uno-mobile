# Deploying Last Card to Coolify

The web app (PWA) is deployed to the DIGISION Coolify instance
(`https://coolify.digision.dev`) as the application **uno-mobile** in the
project **DIGISION-DEV**, served at **https://uno.refandi.my.id**.

| Piece | File |
| --- | --- |
| Server helper (`check`, `install`, `deploy`) | `deploy/coolify/setup.sh` |
| Coolify API provisioner (idempotent) | `deploy/coolify/provision.mjs` |
| Provisioner tests (fake Coolify API) | `deploy/coolify/provision.test.mjs` |
| Image: Flutter 3.50.1 build, nginx runtime (non-root, port 8080) | `Dockerfile`, `deploy/nginx/nginx.conf` |
| Coolify "Docker Compose" build pack | `docker-compose.yml` |
| CI: tests, image smoke test, deploy webhook | `.github/workflows/ci.yml` |

Two services run from `docker-compose.yml`:

| Service | Image target | Role |
| --- | --- | --- |
| `web` | `web` | nginx serving the PWA on port 8080; proxies `/ws` to `server` |
| `server` | `server` | Dart WebSocket game server for online rooms on port 8081 (not public) |

Only `web` gets the domain. Online rooms live in the server's memory: no
database, no secrets, no volumes. A server restart (for example a deploy)
ends the rooms that are open at that moment; players simply create a new one.
Keep one replica of `server`.

## 1. DNS (Cloudflare)

Add a record for `uno.refandi.my.id`:

- Type `A`, name `uno`, value: the server's public IP, **Proxied** (orange cloud).
- SSL/TLS mode for the zone: **Full (strict)**.

If Let's Encrypt cannot issue the first certificate behind the proxy, switch the
record to *DNS only* (grey cloud) until the certificate exists, then back to
Proxied.

## 2. First deploy (on the server, as root)

```bash
curl -fsSL https://raw.githubusercontent.com/freack21/uno-mobile/main/deploy/coolify/setup.sh -o setup.sh
sudo bash setup.sh check
sudo bash setup.sh deploy --domain uno.refandi.my.id
```

`deploy` asks for a Coolify API token (hidden input; create it in Coolify under
*Keys & Tokens* with the **root** permission). It then:

1. checks DNS for the domain;
2. downloads `provision.mjs` from the exact commit of the branch;
3. creates or reuses the app **uno-mobile** in **DIGISION-DEV**
   (the project is created if missing), attaches the domain to the `web`
   service on port 8080, deploys and waits for the build;
4. prints the site URL, health URL and the deploy webhook.

The Flutter build takes a few minutes on the first deploy. The token and domain
are saved to `/etc/uno-mobile/coolify.env` (root only) **after** a successful
run, so a failed first run asks for them again. Use `--reset` to change them.

Options: `--branch <name>` (default `main`), `--project <name>`, `--mirror`
(base images from `mirror.gcr.io` when Docker Hub returns 429), `--yes`.

Re-running `deploy` is safe: it reuses the project and the app and just deploys again.

## 3. Automatic deploys from GitHub Actions

`ci.yml` runs on every push: format, analyze, Flutter tests, provisioner tests,
shellcheck, a Docker build and a container smoke test. Only green pushes to
`main` trigger the deployment.

Add two repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `COOLIFY_DEPLOY_WEBHOOK` | `https://coolify.digision.dev/api/v1/deploy?uuid=<uuid printed by setup.sh>&force=false` |
| `COOLIFY_TOKEN` | a **deploy-only** Coolify token (not the root token) |

Then turn off *Auto Deploy* for the app in Coolify, so only tested commits are
deployed. Without the secrets the deploy job still shows success but is
**skipped** (with a notice).

## 4. Caching and updates

nginx serves:

| Path | Cache-Control |
| --- | --- |
| `main.dart.<hash>.js`, `assets/**` (content-hashed) | `public, max-age=31536000, immutable` |
| everything else (`index.html`, `sw.js`, `flutter_bootstrap.js`, manifests, `canvaskit/**`) | `no-cache` |

The service worker caches the app for offline play. A new deploy is downloaded
in the background and becomes active the next time the app is opened.

## 5. Checks after a deploy

```bash
curl -fsS https://uno.refandi.my.id/healthz          # ok
curl -fsSI https://uno.refandi.my.id/ | grep -i cache-control
curl -fsSI https://uno.refandi.my.id/sw.js | grep -i cache-control
```

Open the site on a phone and use *Install app* (Android/desktop Chrome) or
*Share → Add to Home Screen* (iOS Safari).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `403 You are not allowed to access the API` | Coolify Settings → Advanced: enable API, leave *Allowed IPs* empty or add the `coolify` Docker network subnet printed by the script; use a root token |
| `401` | Token revoked or mistyped: `sudo bash setup.sh deploy --reset` |
| Traefik `404 page not found` | Domain not attached to service `web` with port 8080: re-run `setup.sh deploy` |
| Build fails with `429 Too Many Requests` | `sudo bash setup.sh deploy --mirror` |
| Build fails while cloning Flutter or downloading the Dart SDK | The server needs outbound HTTPS to `github.com`, `storage.googleapis.com` and `pub.dev` |
| Redirect loop / SSL error | Cloudflare SSL mode must be Full (strict) |
| iPhone: app does not fill the screen or the top looks blurred | Fixed by the opaque status bar in `web/index.html`; iOS reads it only when the app is added, so remove the app from the Home Screen and add it again |
| "Cannot reach the game server" | Check that the `server` container is healthy in Coolify; `curl -fsS https://uno.refandi.my.id/healthz` only checks nginx |
| Old version still shown | Close and reopen the app (the new service worker activates on launch); `index.html` and `sw.js` are never cached by nginx |
