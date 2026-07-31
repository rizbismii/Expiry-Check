# Expiry Check — browser link

Non-Android users can open the same shop inventory in a browser.

## Live link (GitHub Pages)

After the first successful deploy from `main`:

**https://rizbismii.github.io/Expiry-Check/**

## What it does

- Auto cloud sync to the same Supabase shop (`expiry-check-shop`)
- Staff / admin login
- Manual add / edit / delete products
- Shared with Android phones — **no data wipe**, existing tables stay as-is

## What stays on Android only

- Camera OCR / barcode scan
- Local push notifications

## One-time GitHub setup

1. Repo → **Settings → Pages**
2. Source: **GitHub Actions**
3. Push to `main` (or run **Deploy Web App** workflow)

## Local build

```bash
flutter build web --release --base-href "/Expiry-Check/"
```

Output: `build/web/`
