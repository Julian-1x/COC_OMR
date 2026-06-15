# Production deployment — COC OMR

Rollout checklist for **ongoing professional use** at Cagayan de Oro College (not a one-off pilot).

## Release gate (before any teacher install)

- [ ] `flutter test` and `flutter analyze` pass
- [ ] APK built with `scripts/build_release.ps1` (Supabase keys from `secrets.json`)
- [ ] Release signed with production keystore (`android/key.properties`) when distributing widely
- [ ] `SCAN_VALIDATION.md` completed on target printer + phone models
- [ ] `PRIVACY.md` contact line updated with school IT / DPO
- [ ] Version in `pubspec.yaml` bumped and noted in release notes

## Teacher onboarding (each cohort)

- [ ] Install signed APK (`edu.coc.omr`) — uninstall old `com.example` builds first
- [ ] Register or sign in online once; create offline PIN
- [ ] Import roster; create answer keys; assign sections correctly
- [ ] Print trial sheets at **100% scale**; scan 10 practice sheets (target ≥ 95% correct)
- [ ] Sync once on school Wi‑Fi; export one JSON backup as a drill

## Exam-day operations

- [ ] Roster and answer keys ready **before** the room
- [ ] Sheets printed Actual size / 100% — same printer settings as validation
- [ ] Teachers use PIN unlock (no Wi‑Fi required during scanning)
- [ ] Flagged scans reviewed via Review queue — never override low confidence blindly
- [ ] After session: **Sync Now** on Wi‑Fi; optional JSON backup before leaving campus

## Ongoing support

| Resource | Audience |
|----------|----------|
| [TEACHER_GUIDE.md](TEACHER_GUIDE.md) | Teachers |
| [SCAN_VALIDATION.md](SCAN_VALIDATION.md) | IT / lead teacher per printer |
| [PRODUCTION.md](PRODUCTION.md) | Sync, backup, device expectations |
| [RELEASE.md](RELEASE.md) | Building and distributing APK |
| [PRIVACY.md](PRIVACY.md) | Data handling |

- Monitor **Sentry** (if `SENTRY_DSN` set in `secrets.json`) for crashes in production.
- Escalation: school IT + developer contact on file.

## Success metrics (production)

- ≥ 95% practice sheets graded correctly without manual fix (per `SCAN_VALIDATION.md`)
- Sync completes on school Wi‑Fi within 5 minutes for typical class sizes
- Zero unexplained data loss (backup restore tested at least once per semester)
- Teachers complete login → scan → sync without developer in the room

## Optional later

- Google Play internal / managed distribution
- MDM push for school-owned devices
- Department-wide Supabase project review and RLS audit
