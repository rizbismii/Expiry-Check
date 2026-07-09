# Expiry Check

A Flutter app for **Android and iOS** that tracks product expiry dates. Point the camera at a product label and on-device AI text recognition extracts the **expiry date, brand name and batch number** automatically. The app reminds you **weekly** (plus per-product alerts before expiry), and can export **Excel reports** and backups you can keep in your own cloud drive.

## Features

- **AI camera scanning** — take a photo of a label; Google ML Kit text recognition (fully offline, free) reads it, and a smart parser extracts:
  - expiry date (handles `EXP 15/08/2026`, `BEST BEFORE 03-12-27`, `12 AUG 2026`, `EXP 08/2026`, `2026-11-05`, compact NZ formats like `EXP: 12052028`, and distinguishes MFG/PRO vs EXP dates)
  - batch / lot number — labelled (`Batch No`, `B.No`, `LOT`, …) or unlabelled codes printed next to the date panel (e.g. `ALY32 260513`)
  - brand name and product/flavour name combined with strength (e.g. "BERRY LEMON 11.4 mg/mL")
  - category guess (e.g. "NICOTINE SALT E-LIQUID" → Salt Liquids)
- **Inventory tracking** — name, brand, batch, category, quantity, notes; color-coded status (expired / expiring ≤ 30 days / fresh), search and filters. Categories: Shisha Flavours, Salt Liquids, Free Base Liquids, Detox Products, Prefilled Vape Pods, Prefilled Kits. Dates are shown and typed in NZ format (dd/mm/yyyy).
- **Store branches** — three branches with editable names (Settings → Store branches). Each branch keeps its own inventory: switch branches from the dropdown in the app bar, and products/scans are saved to the selected branch. Excel reports are generated per branch, and expiry reminders mention the branch name.
- **Notifications**
  - weekly digest on a day/time you choose (default Monday 09:00)
  - per-product alert N days before expiry (3/7/14/30, default 7) and on expiry day
  - reminders survive device reboots on Android
- **Excel reports** — choose the report basis (expiry date or added date) and an optional dd/mm/yyyy date range, then export an `.xlsx` with the inventory (brand, product, expiry, batch, category, quantity, days left, status) plus a summary sheet, shared via the system share sheet (email, WhatsApp, Drive…).
- **Duplicate merging** — adding a product with the same brand, name, batch and expiry as an existing entry in the same store increases its quantity instead of creating a duplicate row.
- **Backup & restore** — export a JSON backup and keep it wherever you like; restore it on any device.

## Storage: local-first (the cost-effective choice)

Data is stored **on-device in SQLite** — zero server or subscription costs, works offline, and is private by default. For cloud durability, the backup/report files are handed to the **system share sheet**, so users can save them to **Google Drive / iCloud / OneDrive storage they already have for free**, instead of the app paying for hosted backend storage (e.g. Firebase). This gives cloud backup at effectively \$0 running cost.

If a hosted sync backend is ever needed (multi-device live sync), the `DatabaseService` is the single integration point to swap in Firestore/Supabase later.

## Tech stack

| Concern | Package |
| --- | --- |
| OCR (on-device AI) | `google_mlkit_text_recognition` |
| Camera capture | `image_picker` |
| Local database | `sqflite` |
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
