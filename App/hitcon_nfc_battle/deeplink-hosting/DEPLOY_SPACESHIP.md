# Deep Link Hosting Package (Spaceship Domain)

This folder is a deploy-ready static site for:

- Android App Links verification (`/.well-known/assetlinks.json`)
- iOS Universal Links verification (`/.well-known/apple-app-site-association`)
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

- Replace `id=com.example.hitcon_nfc_battle` if your final Android package id changes.
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
- `https://game.hitcon2026.online/b`

## 4) Important checks

- Must be HTTPS.
- Do not redirect `/.well-known/*`.
- `apple-app-site-association` must have no `.json` extension.
- Content type should be JSON for both well-known files.

## 5) App-side checklist

- AndroidManifest has host/path for `https://game.hitcon2026.online/b`.
- iOS target has Associated Domains:

```text
applinks:game.hitcon2026.online
```

Without iOS Associated Domains, Universal Links will not open app directly.
