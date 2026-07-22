# Expiry Check

A Flutter app for **Android and iOS** that tracks product expiry dates. Point the camera at a product label and on-device AI text recognition extracts the **expiry date, brand name and batch number** automatically. The app reminds you **weekly** (plus per-product alerts before expiry), and can export **Excel reports** and backups you can keep in your own cloud drive.

## Features

- **AI camera scanning** — take a photo of a label; Google ML Kit text recognition (fully offline, free) reads it, and a smart parser extracts:
  - expiry date (handles `EXP 15/08/2026`, `BEST BEFORE 03-12-27`, `12 AUG 2026`, `EXP 08/2026`, `2026-11-05`, compact NZ formats like `EXP: 12052028`, and distinguishes MFG/PRO vs EXP dates)
  - batch / lot number — labelled (`Batch No`, `B.No`, `LOT`, …) or unlabelled codes printed next to the date panel (e.g. `ALY32 260513`)
  - brand name and product/flavour name combined with strength (e.g. "BERRY LEMON 11.4 mg/mL")
  - category guess (e.g. "NICOTINE SALT E-LIQUID" → Salt Liquids)
- **Inventory tracking** — name, brand, barcode ID, prod date, expiry, batch, category, quantity, notes; color-coded status (expired / expiring ≤ 30 days / fresh), search and filters. Categories: Shisha Flavours, Salt Liquids, Free Base Liquids, Detox Products, Prefilled Vape Pods, Prefilled Kits. Dates are shown and typed in NZ format (dd/mm/yyyy).
- **Store branches** — three branches with editable names (Settings → Store branches). Each branch keeps its own inventory: switch branches from the dropdown in the app bar, and products/scans are saved to the selected branch. Excel reports are generated per branch, and expiry reminders mention the branch name.
- **Notifications**
  - weekly digest on a day/time you choose (default Monday 09:00)
  - per-product alert N days before expiry (3/7/14/30, default 7) and on expiry day
  - reminders survive device reboots on Android
- **Excel reports** — choose the report basis (expiry date or added date) and an optional dd/mm/yyyy date range, then export an `.xlsx` with the inventory (brand, product, expiry, batch, category, quantity, days left, status) plus a summary sheet, shared via the system share sheet (email, WhatsApp, Drive…).
- **Duplicate merging** — adding a product with the same brand, name, batch and expiry as an existing entry in the same store (ignoring case and spacing) prompts to increase its quantity instead of creating a duplicate row.
- **Voice input** — every form field has a microphone button for dictation (on-device speech recognition); spoken dates like "12 May 2028" fill the expiry field in dd/mm/yyyy.
- **Stock dashboard notifications** — weekly or monthly (configurable day and time), showing total units plus Expired / ≤30days / ≤90days / Fresh unit counts, with a per-branch breakdown when multiple stores hold stock.
- **Sign-in with username & password** — the built-in `admin` account (password `admin555777`) creates up to 10 staff accounts in Settings → Manage users (only the admin can see them). After sign-in, the user picks their store branch. The username is stamped on entries ("Added … by …", "Created By" in Excel) and the deletion log.
- **Multi-photo AI scanning** — scan up to 3 photos per product (front for brand/flavour, bottom for expiry/batch); recognized text is combined, and brand guesses are auto-corrected against brands already in the inventory (fixes stylized-logo misreads).
- **Deletion audit** — swiping a row to delete requires a reason/note; deletions are logged and exported as a "Deletion Log" sheet in Excel reports.
- **Duplicate cleanup** — Settings → "Clean up duplicate rows" merges existing duplicates (same brand/product/batch/expiry ignoring case, spacing and punctuation) by combining quantities.
- **Backup & restore** — export a JSON backup and keep it wherever you like; restore it on any device.
- **Optional cloud sync (Supabase)** — live multi-device sync for products, store names and the deletion log. Local SQLite still works offline; changes push/pull when online.

## Storage: local-first + optional Supabase sync

Data is stored **on-device in SQLite** by default — works offline and stays private. Manual backups still go through the share sheet (Drive / iCloud).

For **live multi-device sync**, enable **Settings → Cloud sync**:

1. Create a free project at [supabase.com](https://supabase.com) (one-time), or use your existing one
2. **Existing project:** run [`supabase/schema_migrate_no_email.sql`](supabase/schema_migrate_no_email.sql) in the SQL Editor  
   **New project:** run [`supabase/schema.sql`](supabase/schema.sql)
3. Install the APK and flip **Enable cloud sync → Connect**

No sync email is used (avoids Supabase bounced emails). Staff usernames created under **Manage users** are what people sign into the app with, and those sync across phones.

## Tech stack

| Concern | Package |
| --- | --- |
| OCR (on-device AI) | `google_mlkit_text_recognition` |
| Camera capture | `image_picker` |
| Local database | `sqflite` |
| Cloud sync | `supabase_flutter` |
| Notifications | `flutter_local_notifications` + `timezone` |
| Excel export | `excel` |
| Sharing files | `share_plus` |
| Backup restore picker | `file_picker` |

## Project structure

```
lib/
  main.dart                     # app entry + theme
  models/product.dart           # product entity + expiry status logic
  utils/date_parser.dart        # OCR text -> expiry date / batch / brand parser
  services/
    database_service.dart       # SQLite CRUD
    ocr_service.dart            # ML Kit text recognition
    notification_service.dart   # weekly digest + per-product reminders
    export_service.dart         # Excel report + JSON backup/restore
  screens/
    home_screen.dart            # inventory list, filters, scan FAB
    product_form_screen.dart    # add/edit with scan pre-fill
    settings_screen.dart        # notification schedule, reports, backup
```

## Getting started

```bash
flutter pub get
flutter run          # on a connected Android/iOS device
```

Build releases:

```bash
flutter build apk --release      # Android
flutter build ipa --release      # iOS (requires macOS + Xcode)
```

Run the tests (date/batch/brand parser and model logic):

```bash
flutter test
```

## Permissions

- **Camera** — photographing labels for recognition (Android `CAMERA`, iOS `NSCameraUsageDescription`)
- **Notifications** — expiry reminders (Android 13+ `POST_NOTIFICATIONS`, iOS alert permission)
- **Boot completed** (Android) — re-registers scheduled reminders after restart
