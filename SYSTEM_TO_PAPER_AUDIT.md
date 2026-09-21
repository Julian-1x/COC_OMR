# SYSTEM-TO-PAPER VALIDATION AUDIT
## COC OMR Capstone — Chapters 1–3 vs Implemented System

**Rule:** The implemented system is the source of truth.  
**Paper sources reviewed:**  
- `D:\DOWNLOADS\OPTICAL-MARK-RECOGNITION-OMR-PAPER (1).pdf` (Chapters 1–3 + appendices)  
- `D:\DOWNLOADS\CHAPTER-4_FINAL.pdf` (format only; content is from a different project)

**Status of this document:** Audit only. No chapter rewrite yet.

---

# A. SYSTEM OVERVIEW

## What the system actually is

**COC OMR** is a production offline-first Optical Mark Recognition (OMR) grading product for Cagayan de Oro College teachers. It has three layers:

1. **Mobile app (Flutter)** — exam-day tool for teachers  
   - Online sign-in once (email/password, email verification, admin approval)  
   - Daily unlock with offline PIN  
   - Roster import / sections / students  
   - Answer keys (standard 30–100 and custom full-page portrait layouts)  
   - Shared-key vs section-only answer keys  
   - Printable OMR sheets and OMR ID lists  
   - Phone-camera OMR scanning via **native OpenCV** (Android/iOS)  
   - Scan review for flagged / low-confidence / multi-mark sheets  
   - Auto-capture mode (forces Review before save)  
   - Local SQLite storage  
   - Sync to Laravel API when online  
   - Item analysis and exports on device  

2. **Backend (`coc-omr-api`, Laravel 11 + Sanctum)**  
   - Auth, teacher approval, sync APIs, profile PIN hash backup  
   - Production DB: **PostgreSQL** (SQLite supported for local/dev)  
   - Roles: teacher; school_admin / admin for oversight  

3. **Web portal (`omr_web`, Next.js / React)**  
   - **Teacher desk companion** (not a student portal)  
   - Classes, prepare (roster, keys, print), results, item analysis  
   - School admin views (access control, school overview)  
   - No camera scanner on web (by design)  

## What the system is NOT

- Not a student-facing results portal in the finished production workflow  
- Not MySQL + HTML/vanilla JS as stated in Chapter 3  
- Not React Native / `react-native-opencv`  
- Not “AI OMR” in the sense of a separate ML model product claim  
- Not essay / subjective grading  
- Not half/quarter/landscape custom sheets for new layouts (removed for scan UX)  
- Not cloud upload of scan photos  

## Feature status snapshot

| Area | Status |
|------|--------|
| Teacher auth + email verification + approval | FULLY IMPLEMENTED |
| Offline PIN unlock | FULLY IMPLEMENTED |
| Roster / sections / OMR IDs | FULLY IMPLEMENTED |
| Answer keys (shared + section-only) | FULLY IMPLEMENTED |
| Standard sheet print (30–100) | FULLY IMPLEMENTED |
| Custom full-page portrait sheets | FULLY IMPLEMENTED |
| Half/quarter/landscape new layouts | NOT OFFERED (legacy only if already saved) |
| Native OMR scan + review | FULLY IMPLEMENTED |
| Auto-capture | FULLY IMPLEMENTED |
| Offline SQLite + later sync | FULLY IMPLEMENTED |
| Teacher/admin web portal | FULLY IMPLEMENTED |
| Student web login/results portal | NOT PRESENT |
| Item analysis (difficulty + discrimination) | FULLY IMPLEMENTED |
| Partial credit / multi-answer keys | FULLY IMPLEMENTED |
| Exam Day Board | FULLY IMPLEMENTED |
| Cloudflare Turnstile captcha | FULLY IMPLEMENTED (not math puzzles) |
| Guaranteed 99%+ scan accuracy | NOT PRESENT / UNSUPPORTED as product claim |

---

# B. CHAPTER 1 AUDIT

## Introduction

| Issue | Finding |
|-------|---------|
| EvalBee as current Engineering tool | ACCURATE enough as motivational context IF interviews support it; keep as problem motivation, not as a full competitor audit |
| “Depends heavily on stable internet” | PARTIALLY ACCURATE / NEEDS VERIFICATION — keep as instructor-reported pain point; avoid absolute wording unless documented |
| Ads / free-tier interruptions | ACCURATE as problem motivation for free EvalBee-type tools |
| Lack of detailed analytics | PARTIALLY ACCURATE — EvalBee has some reporting; your gap claim should be “limited / interrupted / not institution-owned analytics,” not “no analytics exist anywhere” |
| Proposed: mobile OMR + web analytics | PARTIALLY ACCURATE — web is teacher/admin sync + analysis, **not** a student analytics portal |

## Statement of the Problem

| Question / claim | Status | Notes |
|------------------|--------|-------|
| Offline OMR without continuous internet | ACCURATE | Matches offline-first design (after one online sign-in + PIN) |
| Eliminate ads / unstable-internet interruptions during scan | ACCURATE | App is ad-free; scanning works offline |
| Detailed performance analytics / reports | PARTIALLY ACCURATE | Item analysis exists for teachers (mobile + web); not a student portal |
| Improve efficiency of checking | ACCURATE as objective | Do not claim measured time savings yet unless Chapter 4 has real data |

**Critical wording risk:** “offline with no internet” must be clarified:

> Offline grading works **after** one online registration/sign-in and PIN setup. Exam day unlock does not need Wi‑Fi. Sync needs internet later.

## Conceptual Framework (IPO)

| Paper element | Status | Actual system |
|---------------|--------|---------------|
| Inputs: sheets, keys, roster | ACCURATE | Yes |
| Mobile OpenCV scanning | ACCURATE | Native OpenCV bridges |
| Offline scoring | ACCURATE | Yes |
| Local SQLite | ACCURATE | Yes |
| JSON web sync | ACCURATE | Laravel sync APIs |
| Automated grades | ACCURATE | With review for risky scans |
| Item analysis | ACCURATE | Difficulty + discrimination |
| “Web portal for instructors **and students**” | **INACCURATE** | Teacher + school admin only |
| “Interactive admin/student visualization” | **OUTDATED / INACCURATE** | Teacher prepare/results + admin oversight |

## Objectives

| Objective | Status |
|-----------|--------|
| Offline-capable OMR app | ACCURATE (with one-time online bootstrap) |
| Ad-free stable scanning | ACCURATE |
| Analytics + item analysis | ACCURATE for teachers |
| Improve efficiency / automate score computation | ACCURATE as goal; measured gains = Chapter 4 only |

## Significance

| Audience claim | Status |
|----------------|--------|
| Institution / Engineering / instructors | ACCURATE as study focus |
| “Students … detailed performance analysis” via system access | **INACCURATE / OVERCLAIMED** unless you mean teachers show/export feedback to students |
| Future researchers | ACCURATE |

Safer student wording:

> Students benefit from faster checking and clearer feedback produced by teachers (exports/printouts), not from a dedicated student login portal.

## Scope and Limitations

| Claim | Status | Correction needed |
|-------|--------|-------------------|
| Mobile for instructors to scan MCQ | ACCURATE | Keep |
| Web allows **students** to view results | **INACCURATE** | Change to teacher/admin portal |
| Engineering-only system | PARTIALLY ACCURATE | Locale may be Engineering; software is school-teacher oriented |
| MCQ only / no essays | ACCURATE | Keep |
| Accuracy affected by print/light/shading | ACCURATE | Keep and strengthen |
| Missing: offline PIN bootstrap | MISSING FROM PAPER | Add |
| Missing: custom full-page sheets | MISSING FROM PAPER | Add |
| Missing: review-before-save / flagged scans | MISSING FROM PAPER | Add |
| Missing: shared vs section-only keys | MISSING FROM PAPER | Add |
| Missing: scan photos stay local | MISSING FROM PAPER | Add under privacy/limitations |

## Definition of Terms

Mostly fine. Issues:

| Term | Status |
|------|--------|
| Performance Analytics Dashboard as student-facing | INACCURATE |
| Web-Based Analytics for instructors and students | INACCURATE |
| AI / computer vision wording | PARTIALLY ACCURATE — OpenCV CV is fine; do not imply generative AI / ML product |
| MySQL elsewhere (Ch3) | INACCURATE vs terms that don’t specify MySQL |

---

# C. CHAPTER 2 AUDIT

## Literature use — general

Chapter 2 is mostly **conceptual support**, not a description of your product. That is acceptable **if** you never imply “our system does X because Study Y did X.”

## Specific issues

| Claim / pattern | Status | Recommended action |
|-----------------|--------|--------------------|
| Digital divide / connectivity literature (Borbon et al.) | ACCURATE as gap framing | Keep; cite properly |
| EvalBee workload studies (Cuerdo & Sinfuego; Silao & Luciano) | ACCURATE as related context | Keep; do not claim you measured 130× speed |
| Küçükkara & Tümer OpenCV accuracy up to 99.76% | ACCURATE as **their** reported result | **Do not** present as your system’s accuracy |
| CheckIt / Pushpa OpenCV feasibility | ACCURATE as related work | Keep as feasibility evidence only |
| “AI algorithms in OMR improve detection” | UNSUPPORTED for **your** system | Soften or remove from claims about *this* product |
| Offline-first + SQLite literature | ACCURATE | Keep |
| Research gap: offline-first + ad-free + web analytics for PH Engineering | PARTIALLY ACCURATE | Refine web analytics to **teacher/admin sync portal**, not student portal |
| Gap #2 “instructors and students longitudinal portal” | **INACCURATE vs system** | Rewrite gap to teacher-owned sync + item analysis |

## Citation / evidence rules

- Do **not** invent references.
- Typographical issues in reference list (missing spaces, “et al” formatting) are **editorial**, not system mismatches — fix later.
- Any accuracy percentage from foreign studies must be labeled as **prior study findings**, never as COC OMR measured accuracy unless Chapter 4 proves it.

---

# D. CHAPTER 3 AUDIT

## Research design / respondents / locale

| Claim | Status |
|-------|--------|
| Developmental + descriptive-evaluative design | ACCURATE as method (if followed) |
| Instructors 5–7; students 30–40 for usability | NEEDS VERIFICATION | Only keep if you actually evaluated those groups; **student portal SUS does not match system** |
| Engineering locale | ACCURATE as study locale |

**High risk:** evaluating “students using the web analytics portal” when that portal is not implemented for students.

Safer:

> Usability evaluation focuses on instructors (mobile + teacher web). Student benefit is measured indirectly (faster release / feedback documents), if at all.

## Functional requirements (paper list)

| Paper FR | Status vs system |
|----------|------------------|
| Camera capture OMR | FULLY IMPLEMENTED |
| OpenCV detect/evaluate | FULLY IMPLEMENTED |
| Offline checking | FULLY IMPLEMENTED (after online bootstrap) |
| Local SQLite | FULLY IMPLEMENTED |
| Sync when online | FULLY IMPLEMENTED |
| Item analysis for instructors | FULLY IMPLEMENTED |
| **Students securely view results via web portal** | **NOT PRESENT** |
| Batch scanning | FULLY IMPLEMENTED |
| HTTPS sync | FULLY IMPLEMENTED |
| Role-based access Instructor/Student/Admin | PARTIALLY ACCURATE — **Teacher + school_admin**; no student role |

## Non-functional / OMR / sync design

| Claim | Status |
|-------|--------|
| Offline-first queue sync | ACCURATE |
| Perspective correction / thresholding / bubble analysis | ACCURATE at pipeline level |
| “Consistent recognition under normal lighting” | PARTIALLY ACCURATE | True as design goal; not a proven guarantee |
| Instructors access class data; students only own results | **INACCURATE** | Students do not log into web; teachers own data; admins read school-wide |

## Database design table in Ch3

| Paper | Actual | Status |
|-------|--------|--------|
| Local SQLite | Local SQLite | ACCURATE |
| Central MySQL | PostgreSQL production / SQLite dev | **INACCURATE / OUTDATED** |

## Development / tech stack (critical)

| Paper | Actual | Status |
|-------|--------|--------|
| Flutter 0.72+ | Flutter app, Dart SDK `>=3.0.0 <4.0.0` | **INACCURATE** |
| OpenCV react-native-opencv 4.8+ | Native Android/iOS OpenCV bridges in Flutter | **INACCURATE** |
| Web HTML + Vanilla JS | Next.js 16 + React 19 + TypeScript | **INACCURATE / OUTDATED** |
| Backend PHP 10+ | Laravel 11, PHP 8.2+ | **INACCURATE** |
| MySQL 8.0+ | PostgreSQL production | **INACCURATE** |
| Node.js for mobile OMR | Not the mobile stack | OUTDATED / confusing |

## Security / ethics claims

| Claim | Status | Risk |
|-------|--------|------|
| HTTPS/TLS | ACCURATE | Keep |
| Role-based access | PARTIALLY ACCURATE | Teacher-owned rows + admin; no student portal |
| “Grade encryption during sync” | OVERCLAIMED | Transport encryption ≠ field-level grade encryption |
| “No sensitive student info stored unencrypted on mobile” | **INACCURATE** | Names, roster, scores stored locally for offline use; PIN is hashed; photos local-only |
| Informed consent / institutional approval | NEEDS VERIFICATION | Keep only if documents exist |

## Appendices / FR matrix (Appendix O)

Student portal FRs (FR-01 student login, FR-19 student portal, FR-02 Student role) are **INACCURATE** relative to the shipped system and must be revised before defense.

---

# E. PAPER VS SYSTEM TABLE

| Chapter/Section | Statement/Claim | What the Paper Says | What the System Actually Does | Status | Recommended Action |
|-----------------|-----------------|---------------------|-------------------------------|--------|---------------------|
| Ch1 Intro / Scope | Student web portal | Students view results/item analysis on web | Teacher/admin portal only; no student app routes | INACCURATE | Rewrite: students benefit via teacher-released feedback/exports |
| Ch1 IPO Output | Web portal for instructors and students | Interactive portal for both | Teacher prepare/results + admin oversight | INACCURATE | Remove student actor from web output |
| Ch1 Significance | Students get detailed performance analysis | Implies system access | No student login | PARTIALLY ACCURATE | Soften to indirect benefit |
| Ch1 Scope | Engineering-only product | Dept of Engineering only | Locale may be Engineering; product is COC teachers | PARTIALLY ACCURATE | Separate study locale from software extensibility |
| Ch1 Limitations | Standard layouts implied | Standard OMR layouts | Also custom full-page portrait | OUTDATED / MISSING FROM PAPER | Add custom sheets; note half/quarter not offered for new layouts |
| Ch1 | Offline capability | Works without internet | Needs one online sign-in + PIN first | PARTIALLY ACCURATE | Clarify bootstrap model |
| Ch1 | Review / confidence workflow | Barely mentioned | Core production safety feature | MISSING FROM PAPER | Add to scope/objectives/process |
| Ch1 | Shared vs section-only keys | Not described | Implemented with badges/guards | MISSING FROM PAPER | Add to scope/features |
| Ch2 | 99.76% accuracy | Cited from foreign study | Not your measured accuracy | UNSUPPORTED (as product claim) | Keep as related literature only |
| Ch2 | AI in OMR | Implies modern AI boost | Your engine is OpenCV CV, not marketed AI model | UNSUPPORTED for product | Soften wording |
| Ch2 Research Gap | Student+instructor longitudinal portal | Gap includes students | Gap should be teacher-owned offline-first + sync analytics | INACCURATE vs system | Rewrite gap |
| Ch3 Actors | Instructor + Student | Students use secure web portal | Actors: Teacher, School Admin | INACCURATE | Replace Student web actor |
| Ch3 DB | Central MySQL | MySQL stores consolidated records | PostgreSQL production | INACCURATE | Correct tech table |
| Ch3 Stack | Flutter 0.72+ | Listed | Invalid Flutter/Dart 3.x | INACCURATE | Correct version wording |
| Ch3 Stack | react-native-opencv | Listed | Flutter + native OpenCV | INACCURATE | Correct |
| Ch3 Stack | HTML/Vanilla JS | Listed | Next.js/React/TS | INACCURATE | Correct |
| Ch3 Stack | PHP 10+ | Listed | Laravel 11 / PHP 8.2+ | INACCURATE | Correct |
| Ch3 Security | Unencrypted local student data denied | Claims no unencrypted sensitive local data | Local roster/scores exist for offline | INACCURATE | Rewrite privacy claim |
| Ch3 Security | Grade encryption | Claims encrypted grades in sync | HTTPS/TLS + auth tokens | PARTIALLY ACCURATE | Say transport security |
| Ch3 Respondents | Student portal usability | 30–40 students evaluate web analytics | No student portal to evaluate | OUTDATED / RISKY | Change evaluation design or build portal (paper adjusts; system stays) |
| Ch3 FR list | FR-19 student portal | Required | Not implemented | INACCURATE | Remove or reclassify as out of scope |
| Appendix A/L mockups | Student Dashboard screens | Shown in appendices | Not in production web | OUTDATED | Relabel as early concept or remove |
| Ch4 PDF (format file) | Booking/field-worker system | Entire chapter content | Wrong project | INACCURATE | Use structure only; rewrite content for OMR |
| Entire paper | Ad-free scanning | Claimed | True for COC OMR app | ACCURATE | Keep |
| Entire paper | Offline SQLite + later sync | Claimed | True | ACCURATE | Keep |
| Entire paper | OpenCV phone scanning | Claimed | True (native) | ACCURATE | Keep wording precise |
| Entire paper | Item analysis | Claimed | True (difficulty + discrimination) | ACCURATE | Keep; specify teacher-side |
| Missing | Offline PIN | Not emphasized | Core offline UX | MISSING FROM PAPER | Add |
| Missing | Teacher approval gate | Not emphasized | Pending until admin approves | MISSING FROM PAPER | Add in auth/security |
| Missing | Turnstile captcha | Not mentioned | Used on login/register when required | MISSING FROM PAPER | Optional mention in security |
| Missing | Scan photos local-only | Not clear | PRIVACY.md: photos not synced | MISSING FROM PAPER | Add to privacy/limitations |
| Missing | Exam Day Board | Not mentioned | Implemented | MISSING FROM PAPER | Add as feature |
| Missing | Partial credit / multi-answer | Not clear in Ch1–3 | Implemented | MISSING FROM PAPER | Add if in scope of evaluation |

---

# F. HIGH-RISK CLAIMS (Defense Risk List)

These can get you challenged if left as written:

1. **“Students securely access and view their examination results through a web-based portal.”**  
   - Risk: panel asks for demo → you cannot show student login.  
   - Safer: “Teachers and authorized administrators access synchronized results through the web portal; student feedback can be exported/shared by teachers.”

2. **“No sensitive student information is stored unencrypted on mobile devices.”**  
   - Risk: privacy panel question; false.  
   - Safer: “Roster and scores are stored locally to support offline grading. Offline PIN is hashed. Scan photos remain on-device and are not uploaded.”

3. **“Grade encryption during synchronization.”**  
   - Risk: overclaims cryptography.  
   - Safer: “Synchronization uses authenticated HTTPS/TLS.”

4. **Any implication that COC OMR achieves ~99.76% accuracy.**  
   - Risk: literature number attributed to your product.  
   - Safer: cite as prior OpenCV study; report only your measured validation.

5. **Central database is MySQL / web is HTML+JS / OpenCV is React Native.**  
   - Risk: technical panel will open your repo.  
   - Safer: Laravel 11, PostgreSQL, Next.js, Flutter + native OpenCV.

6. **“Works without internet” without stating one-time online bootstrap.**  
   - Risk: demo requires register/sign-in first.  
   - Safer: clarify PIN unlock after initial online account setup.

7. **“Completely eliminates interruptions / guarantees consistent recognition.”**  
   - Risk: absolute language.  
   - Safer: “reduces dependence on continuous connectivity; recognition depends on print, lighting, shading, and framing.”

8. **Student Dashboard mockups in appendices if presented as final UI.**  
   - Risk: “where is this screen?”  
   - Safer: mark as early concept discarded, or remove.

9. **Chapter 4 template numbers (84.5 SUS, 4.61 ISO, 88% speedup, booking modules).**  
   - Risk: obvious wrong-system content.  
   - Action: format only; invent nothing.

10. **“100% verified / 100% pass rate” style language from the wrong Chapter 4.**  
   - Do not import into OMR Chapter 4 unless your documented tests support it.

---

# G. MISSING FEATURES / INFORMATION IN THE PAPER

Implemented in system but weak/absent in Chapters 1–3:

| Implemented feature | Where to document |
|---------------------|-------------------|
| Offline PIN after online sign-in | Ch1 scope; Ch3 auth design; Ch4 screens |
| Teacher approval (`pending` → admin approve) | Ch3 security/access control |
| Shared vs section-only answer keys + print tags + scan guards | Ch1 scope; Ch3 exam management; Ch4 demo |
| Custom full-page portrait sheets (A–F options, capacity limits) | Ch1 scope/limitations; Ch3 print module |
| Review before save / flagged questions / confidence | Ch1 process; Ch3 OMR design; Ch4 testing |
| Auto-capture mode | Ch3 scanner features; Ch4 optional |
| Exam Day Board (missing/review/done/absent) | Ch3/Ch4 features |
| Item analysis discrimination index | Ch3 analytics; Ch4 results |
| Partial credit / multi-answer keys | Ch3 exam management if in scope |
| Cloudflare Turnstile (not math captcha) | Ch3 security (brief) |
| Scan photos local-only; not synced | Ch1 limitations; ethics/privacy |
| School admin web oversight | Ch3 actors/roles |
| Native OpenCV Android + iOS bridges | Ch3 tech stack |
| Laravel Sanctum API sync model | Ch3 architecture |
| Next.js teacher portal modules (Classes / Prepare / Results / Admin) | Ch3 UI design |

---

# H. RECOMMENDED REVISIONS (Priority)

## 1. Critical corrections (do before defense)

1. Remove/replace **student web portal** claims everywhere (Ch1 IPO, scope, significance, Ch3 actors/FRs, appendices).  
2. Fix **technology stack** (Flutter, native OpenCV, Laravel 11, Next.js, PostgreSQL).  
3. Fix **privacy/security overclaims** (local data + HTTPS wording).  
4. Discard wrong **Chapter 4 content**; keep format only.  
5. Clarify **offline-first = after online account bootstrap**.  
6. Align **research respondents** with real evaluators (instructors/admins), not student-portal users.

## 2. Important corrections

1. Add **review/confidence** as a core academic integrity feature.  
2. Add **shared vs section-only keys**.  
3. Add **custom full-page** support and capacity limits.  
4. Rewrite research gap to match teacher-owned sync analytics.  
5. Separate literature accuracy numbers from your product claims.  
6. Update mockups/appendices so they match shipped screens.

## 3. Minor wording improvements

1. Prefer “reduces / supports / enables” over “eliminates / guarantees / 100%.”  
2. Prefer “teacher desk portal” over “student dashboard.”  
3. Prefer “OpenCV-based computer vision” over vague “AI.”  
4. Clean reference formatting later (editorial).  
5. Mention exam-day constraints (print scale 100%, lighting, HB/2B shading).

---

# I. CHAPTER 4 PREPARATION

Use `CHAPTER-4_FINAL.pdf` **only as a section skeleton**. Replace every module name and metric with OMR facts. Do **not** invent numbers.

## Suggested Chapter 4 outline (aligned to actual system)

### 4.1 System Requirements Analysis
- Map finished modules to FRs that are true for teachers/admins  
- Explicitly mark student-portal FRs as **out of scope / removed** if paper previously required them  

### 4.1.1 Functional Verification Matrix
Suggested true modules:
- Auth + approval  
- Offline PIN  
- Roster/sections  
- Answer keys (shared/section-only)  
- Print sheets (standard/custom)  
- OMR scan + review  
- Local storage  
- Sync  
- Teacher/admin web results + item analysis  

Status language: “Verified through functional testing / demonstration” — only if you actually tested.

### 4.1.2 Non-Functional Verification
- Suitability, reliability (offline-first), performance (qualitative unless measured), usability (SUS if done), security (auth/TLS/PIN hash/RBAC), portability (Android/iOS + browsers)

### 4.2 Features and Functionalities
**4.2.1 Mobile**
- Screenshots: login/PIN, roster, answer key, print, scanner, review, item analysis, sync  

**4.2.2 Web**
- Screenshots: Classes, Prepare, Results/Analysis, Admin access  
- State clearly: no student login  

### 4.3 Architecture and Design
- Use Case: Teacher, School Admin (not Student portal user)  
- DFD / ERD matching actual entities: sections, students, subjects/keys, scan_results, sync fields  
- Architecture: Flutter + native OpenCV + SQLite ↔ Laravel API ↔ PostgreSQL ↔ Next.js  

### 4.4 Evaluation (real data only)
- ISO/IEC 25010 means from **your** forms  
- SUS from **your** respondents  
- Functional test summary from **your** test log / `flutter test` evidence (do not invent pass counts)  
- Optional OMR accuracy comparison vs manual scoring on printed samples (`SCAN_VALIDATION.md` process)  
- Pre/post workflow discussion without fake percentages  

### 4.5 Discussion
- Offline exam-day value  
- Review-before-save integrity  
- Sync later model  
- Honest limits: print/light/shading; custom capacity; no essay grading; no student portal  

### 4.6 Summary of Findings
Only findings you can demonstrate.

## Evidence already available in the repo (for Chapter 4 methods, not fake results)

- Automated tests under `test/` (layout contracts, scan identity, item analysis, imports, etc.)  
- `SCAN_VALIDATION.md` checklist for real printer+phone validation  
- `PRIVACY.md` for data handling claims  
- Release APK process via `scripts/build_release.ps1`

## Explicit non-inventions for Chapter 4

Do not invent:
- respondent counts  
- SUS/ISO means  
- accuracy %  
- time savings %  
- “100% pass rate”  
- booking/field-worker metrics from the template PDF  

---

# Bottom line

Chapters 1–3 are **directionally right** (offline-first teacher OMR + later web sync/analytics), but they still contain **defense-breaking mismatches**, mainly:

1. **Student web portal** (does not exist)  
2. **Wrong technology stack** (MySQL / vanilla JS / React Native OpenCV / PHP 10 / Flutter 0.72)  
3. **Overstrong privacy/security claims**  
4. **Missing major shipped features** (PIN, review, shared keys, custom sheets, admin role)  
5. **Chapter 4 template content from another system**

Next step after your review: rewrite Chapters 1–3 claim-by-claim (paper only), then draft Chapter 4 using the OMR outline above with placeholders for real evaluation data.
