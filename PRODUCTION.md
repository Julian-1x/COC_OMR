# Running OMR in production (short guide)

## Devices and scanning

- **Live bubble reading** uses native OpenCV on **Android** and **iOS** (same `opencv` channel as Android). Use a recent phone or tablet with a working camera and good light.
- **iPhone / iOS**: run `cd ios && pod install` once (OpenCV via CocoaPods), then build from Xcode or `flutter build ios`. First build downloads the OpenCV pod and can take several minutes.
- **Windows / desktop**: treat as **hub** (roster, keys, PDFs) unless you add a native reader for that platform.

## Printing answer sheets

- Export or print PDFs from the app at **100% scale** (“Actual size”). Avoid “Fit to page” if it shrinks the form.
- Use **white A4** (or the size your template assumes), clean printer, enough toner/ink so corner marks and bubbles are sharp.
- Same printer settings for **all** sheets in one exam session when possible, so bubble size stays consistent.

## During scanning

- Use **Review** when the app flags **low confidence**, **needs review**, or **multiple marks** on a question (no auto-guess).
- Prefer a **stable** camera, even lighting, and the sheet **flat** and fully in frame.

## Before exam day

- **Import roster** and **answer keys** ahead of time; do a **trial scan** on a few printed samples.
- **Backup** data (app backup / export) before high-stakes sessions so you can recover from device loss.

## Support expectations

This app stores data **locally** on the device (with optional cloud sign-in). Plan who keeps devices charged, who exports results, and how you handle **retakes** (rescan from the review queue or scanner).

## Data flow and sync

- **Scanning and grading always work offline.** Data is saved to SQLite on the phone first.
- **Cloud sync (Supabase, free tier)** is optional. It stores roster, answer keys, and scan results as JSON — not scan photos.
- **Online login** is required once when registering or moving to a new phone. After that, unlock with your **offline PIN** even without internet.
- **Sync later:** when Wi‑Fi is available, open Settings and tap **Sync Now**, or use the prompt when the app detects internet again.
- **Switching phones:** sync the old phone once, then sign in on the new phone. The app downloads your cloud data automatically after login.
- **Account required:** teachers must register or sign in online once. The release APK must include Supabase keys. Offline PIN unlock works after that; **Sync Now** uploads data to their account.

### Supabase setup (one-time)

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your_publishable_key
```

Run `supabase/schema.sql` in the Supabase SQL Editor before first teacher sign-up.

## Release builds and crash reporting

See [RELEASE.md](RELEASE.md) for signed APK steps (app ID: `edu.coc.omr`).

Optional crash reporting — add when building:

```bash
--dart-define=SENTRY_DSN=https://...@sentry.io/...
--dart-define=SENTRY_ENVIRONMENT=production
```

Create a free project at [sentry.io](https://sentry.io), copy the Flutter DSN, and pass it at build time. Teachers never see Sentry; you use it to monitor crashes in production.

Teacher-facing docs: [TEACHER_GUIDE.md](TEACHER_GUIDE.md) · Exam checklist: [SCAN_VALIDATION.md](SCAN_VALIDATION.md)
