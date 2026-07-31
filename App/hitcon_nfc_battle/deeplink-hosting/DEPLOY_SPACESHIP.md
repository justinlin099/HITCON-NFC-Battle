# Deep Link Hosting Package (Spaceship Domain)

This folder is a deploy-ready static site for:

- Android App Links verification (`/.well-known/assetlinks.json`)
- iOS Universal Links verification (`/.well-known/apple-app-site-association`)
- App API routing config (`/.well-known/nfc-battle-app-config.json`)
- Store fallback page (`/b`)

## 1) Replace placeholders first

### `/.well-known/assetlinks.json`

- `REPLACE_WITH_YOUR_RELEASE_CERT_SHA256`

Get SHA256 from your release signing cert:

```powershell
keytool -list -v -keystore <path-to-keystore> -alias <alias>
```

### `/.well-known/apple-app-site-association`

- `REPLACE_WITH_APPLE_TEAM_ID`

Get Team ID from Apple Developer account.

### `/b/index.html`

- Android package id is `org.hitcon.nfcbattle`.
- Replace `idREPLACE_WITH_APP_STORE_ID` with your real App Store ID.

## 2) Host recommendation for Spaceship domain

Recommended: **Cloudflare Pages** (free and stable for well-known files).

### Steps

1. Create a Cloudflare Pages project.
2. Deploy this folder (`deeplink-hosting`) as the site root.
3. In Spaceship DNS, set `game` subdomain CNAME to Cloudflare Pages target.
4. Enable SSL/HTTPS in Cloudflare.

## 3) Required URLs must be reachable

After deploy, these URLs must return **200**:

- `https://game.hitcon2026.online/.well-known/assetlinks.json`
- `https://game.hitcon2026.online/.well-known/apple-app-site-association`
- `https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json`
- `https://game.hitcon2026.online/b`

## 4) Important checks

- Must be HTTPS.
- Do not redirect `/.well-known/*`.
- `apple-app-site-association` must have no `.json` extension.
- Content type should be JSON for all three well-known files.
- Keep `nfc-battle-app-config.json` on `Cache-Control: no-store`; the included
  Cloudflare Pages `_headers` file applies this automatically.

## 5) Switching the API without releasing a new app

Edit `/.well-known/nfc-battle-app-config.json` and redeploy the static site:

```json
{
  "schema": 1,
  "api_base_url": "https://nfc-battle-staging.hitcon2026.online",
  "allow_user_tag_unlock": true
}
```

The App checks this file on each cold launch and when returning to the
foreground. It accepts only HTTPS API URLs on `hitcon2026.online` or one of its
subdomains. Keep the JSON publicly readable, do not put tokens or secrets in
it, and purge the CDN cache after changing it.

Set `allow_user_tag_unlock` to `false` to keep the attendee unlock button
visible but disabled. This flag does not affect the STAFF unlock tool. The App
uses the last successfully downloaded value while the config site is offline.

## 6) App-side checklist

- AndroidManifest has host/path for `https://game.hitcon2026.online/b`.
- iOS target has Associated Domains:

```text
applinks:game.hitcon2026.online
```

Without iOS Associated Domains, Universal Links will not open app directly.
