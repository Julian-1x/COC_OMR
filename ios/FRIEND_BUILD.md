# iOS experiment branch — friend MacBook build

**Branch:** `ios-experiment`  
**Safe restore point:** `main` on GitHub (`origin/main`)

This branch is for Apple / TestFlight work only. Do **not** merge to `main` until a real iPhone soak passes.

## How Julian goes back to the safe system

```bash
git checkout main
git pull origin main
```

Optional — delete the experiment branch later (local + GitHub):

```bash
git checkout main
git branch -D ios-experiment
git push origin --delete ios-experiment
```

## What this branch already includes

- Bundle ID: `edu.coc.omr`
- Display name: COC OMR
- OpenCV via CocoaPods (`ios/Podfile`)
- Camera + photo library usage strings in `ios/Runner/Info.plist`

## Friend MacBook steps

1. Clone (or pull) the repo:
   ```bash
   git clone https://github.com/Julian-1x/COC_OMR.git
   cd COC_OMR
   git checkout ios-experiment
   ```
2. Install Flutter (stable) and Xcode; open once to accept licenses.
3. Get `secrets.json` **privately** (never commit it). Copy from Julian or from `secrets.json.example` and fill `API_BASE_URL`.
4. From repo root:
   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   flutter build ios --release --dart-define-from-file=secrets.json
   ```
5. Open `ios/Runner.xcworkspace` in Xcode.
6. Select Team (prefer **COC / school Apple Developer team**, not a personal team that will own the Bundle ID forever).
7. Product → Archive → Distribute → **TestFlight**.
8. Smoke on a **real iPhone**: sign-in → PIN → print sample → scan → review → sync.

## Rules so main stays safe

- Commit Apple work on `ios-experiment` only.
- Prefer changes under `ios/` unless a tiny shared Dart fix is required.
- Do not commit `secrets.json`, keystores, or `.p12` files.
- Do not merge to `main` until Julian says so.

## If something breaks

Julian switches back to `main` (commands above). The production Android/web tree on `main` is unchanged by this branch until an intentional merge.
