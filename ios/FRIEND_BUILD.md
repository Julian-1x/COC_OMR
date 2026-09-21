# iOS handoff — solidify first, then friend builds, then teachers

**Branch:** `ios-experiment` only  
**Safe restore:** `main` / `origin/main` (Julian: ask Cursor “switch me back to main”)

Teachers must **not** be invited to TestFlight until the Mac soak below passes.

---

## A. Already solidified in this repo (done on Windows)

| Item | Status |
|------|--------|
| Bundle ID `edu.coc.omr` | Yes |
| Display name COC OMR | Yes |
| Native OpenCV bridge (`OmrNativeBridge` + `OpenCvIosPlugin`) | Yes — wired in Xcode + AppDelegate |
| CocoaPods OpenCV2 in `Podfile` | Yes |
| Camera + photo library privacy strings | Yes |
| Export compliance flag (`ITSAppUsesNonExemptEncryption` = false) | Yes |
| App icons regenerated from brand `assets/app_icon.png` | Yes |
| Same Dart app as Android (sign-in, PIN, scan, review, sync) | Yes |

You cannot finish signing / Archive / real-camera proof on Windows. That is normal.

---

## B. Still required on the MacBook (friend) — before any teacher download

1. **Apple Developer team** (prefer school/COC, not personal forever ownership of Bundle ID).
2. Clone this branch + private `secrets.json` (`API_BASE_URL` must match production API).
3. Build:
   ```bash
   git clone https://github.com/Julian-1x/COC_OMR.git
   cd COC_OMR
   git checkout ios-experiment
   # place secrets.json here (do not commit)
   flutter pub get
   cd ios && pod install && cd ..
   flutter build ios --release --dart-define-from-file=secrets.json
   open ios/Runner.xcworkspace
   ```
4. Xcode → select **Team** → Product → **Archive** → upload to App Store Connect.
5. **Internal soak on 1–2 real iPhones** (not Simulator):
   - Sign in / approval if needed  
   - Offline PIN unlock  
   - Print sample sheet at 100%  
   - Scan with camera (OpenCV must read)  
   - Review-before-save / Scan Confidence  
   - Sync Now → web results appear  
6. Only after soak is clean → add more TestFlight testers.

If soak fails, **do not** invite teachers. Fix on `ios-experiment`, rebuild, soak again.

---

## C. Julian: go back to safe Android/web system anytime

```bash
git checkout main
git pull origin main
```

Or tell Cursor: **“switch me back to main.”**

Optional cleanup later:

```bash
git checkout main
git branch -D ios-experiment
git push origin --delete ios-experiment
```

---

## D. Rules

- Apple work stays on `ios-experiment` until soak passes and Julian approves merge.
- Prefer `ios/` changes; shared Dart only if required for iPhone.
- Never commit `secrets.json`, `.p12`, or keystores.
- Friend builds whenever ready; **teachers download only after soak**.
