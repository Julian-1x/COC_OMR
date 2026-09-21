# CHAPTER 4
## PRESENTATION, ANALYSIS, AND INTERPRETATION OF DATA

**Status:** Content + format applied in `COC_OMR_Chapters_1_4_REVISED.docx` (same Ch1–3 visual rules).  
**Format source for layout:** original Chapters 1–3 PDF metrics (`paper_format_extract/FORMAT_SPEC.md`).  
**Section skeleton only from:** `CHAPTER-4_FINAL.pdf` (booking/field content discarded).  
**Forbidden:** booking/scheduling/field-worker content, invented SUS/ISO scores, invented pass rates, invented time-savings percentages.

Replace every `[Insert …]` marker with figures from your completed instruments or test log. If a metric was not measured, **delete that table** instead of estimating.

---

This chapter presents the results of the testing and evaluation of the developed **Hybrid Offline-First Optical Mark Recognition (OMR) Scanning System with Web-Based Grade Synchronization and Analytics**. The discussion is limited to the completed system: a Flutter mobile application for teacher-side scanning and grading, a Laravel 11 backend for authentication and synchronization, and a Next.js web portal for synchronized academic preparation and result analysis.

The purpose of this chapter is to show how the developed system satisfies its intended functional requirements, how its major components operate, and how it performed under the evaluation instruments actually administered. Claims that cannot be demonstrated in the running software or in completed evaluation forms are omitted.

---

## 4.1 System Requirements Analysis

The developed system was checked against the functional and non-functional requirements established during requirements gathering. Verification focused on the modules that exist in the software: teacher authentication and approval, offline PIN unlock, roster and answer-key management (including shared and section-only keys), printable standard and custom full-page sheets, camera-based OMR scanning with review-before-save, local SQLite storage, later API synchronization, and teacher/administrator web viewing of synchronized records.

The completed system addresses the grading problems identified in Chapter 1 by allowing instructors to prepare class records, scan answer sheets on a mobile device, review flagged readings, save results locally without continuous internet access, and synchronize academic records later. This structure supports exam-day operation when campus connectivity is unstable. It does not provide a student login portal.

### Table 4.1 Level 1 — Unit Testing

Unit testing examined individual functions and services in the mobile and web codebases (for example, answer-key scope, item-analysis calculations, roster import rules, and layout/scannability contracts).

| Testing level | Total tests | Passed | Failed | Pass rate |
|---------------|------------:|-------:|-------:|----------:|
| Unit testing | [Insert from `flutter test` / web test log] | [Insert] | [Insert] | [Insert] |

**Interpretation.**  
[Insert only after you have a real test count.] Suggested wording once filled:

> Unit tests were used to check isolated scoring, layout, and data rules before classroom demonstration. The recorded totals show [Insert interpretation]. These tests support internal consistency; they do not replace printed-sheet accuracy trials.

If you did not keep a unit-test log, write a qualitative sentence instead of a numeric table:

> Automated unit tests in the project repository cover answer-key scope, item analysis, roster import, and sheet-geometry contracts. A numbered pass-rate table is omitted because a formal test-run total was not recorded for this chapter.

### Table 4.1.1 Level 2 — Integration Testing

Integration testing examined the connections among the mobile client, local SQLite database, Laravel API, and web portal.

| Integration path | Result | Notes |
|------------------|--------|-------|
| Mobile application ↔ local SQLite | [Pass / Fail / Not logged] | Offline save of roster, keys, and scores |
| Mobile application ↔ Laravel API (auth) | [Pass / Fail / Not logged] | Sign-in, verification, token use |
| Mobile application ↔ Laravel API (sync) | [Pass / Fail / Not logged] | Upload/download of sections, students, subjects, scan results |
| Web portal ↔ Laravel API | [Pass / Fail / Not logged] | Classes, Prepare, Results, Admin |
| Scan photos uploaded to server | Not applicable | Photos remain on the device by design |

**Interpretation.**  
[Insert based on actual integration checks.] Safe qualitative fallback:

> Integration checks confirmed that records written on the phone can later appear in the teacher web portal after a successful sync. Scan photographs are excluded from synchronization, which matches the privacy design of the system.

### Table 4.1.2 Level 3 — System Testing

System testing exercised complete teacher workflows rather than single functions.

| End-to-end scenario | Result | Notes |
|---------------------|--------|-------|
| Register → verify email → admin approve → set PIN | [Insert] | Online bootstrap required once |
| Unlock offline with PIN and open a section | [Insert] | No Wi-Fi required after bootstrap |
| Create shared or section-only answer key and print sheets | [Insert] | Full-page portrait; 100% print scale |
| Scan sample sheets → review flags → save scores | [Insert] | Review required for risky/auto-capture scans |
| View Exam Day Board (missing / review / done / absent) | [Insert] | Mobile only |
| Sync when online → view results and item analysis on web | [Insert] | Teacher/admin portal |
| Student logs in to view personal results | Out of scope | No student portal in the implemented system |

**Interpretation.**  
[Insert.] Safe qualitative fallback:

> System testing followed the real exam-day path: prepare, print, scan, review, store locally, and sync later. The web portal was verified as a teacher/administrator companion, not as a scanning station and not as a student portal.

---

## 4.1.1 Functional Requirements Verification Matrix

Table 4.2 presents the functional verification matrix for the **implemented** modules. Status language is limited to demonstration and testing that the researchers actually performed. “100% verified via automated logs” is not used.

**Table 4.2.** Requirements traceability and functional verification matrix

| Module ID | Target functional requirement | Verification status | Operational outcome |
|-----------|-------------------------------|---------------------|---------------------|
| FR-01 | Authorized teachers can register, verify email, and sign in | [Verified / Pending evaluation] | The same account is used on mobile and web. New teachers remain pending until a school administrator approves them. |
| FR-02 | Offline unlock after initial account setup | [Verified / Pending evaluation] | Teachers can reopen the app with a hashed offline PIN without internet. |
| FR-03 | Section and roster management | [Verified / Pending evaluation] | Teachers can create or sync sections and maintain student names, school IDs, and OMR IDs. |
| FR-04 | Answer-key creation, including shared and section-only keys | [Verified / Pending evaluation] | Keys can be limited to one section or shared across linked sections. Partial credit is available for multi-answer items. |
| FR-05 | Generation of printable OMR materials | [Verified / Pending evaluation] | Standard 30–100 sheets, scan-safe custom full-page portrait sheets, and OMR ID lists can be printed. |
| FR-06 | Camera-based OMR processing using OpenCV | [Verified / Pending evaluation] | The phone captures the sheet; native OpenCV on Android/iOS reads marks against the printed layout contract. |
| FR-07 | Review of risky or ambiguous scans | [Verified / Pending evaluation] | Flagged, low-confidence, or multi-mark items can be inspected before the score is saved. Auto-capture requires review. |
| FR-08 | Local storage during offline operation | [Verified / Pending evaluation] | Roster, keys, and scores persist in SQLite. Scan photos stay on the device. |
| FR-09 | Synchronization of records when connectivity is available | [Verified / Pending evaluation] | Teachers upload/download academic records through the Laravel API over HTTPS. Photos are not synced. |
| FR-10 | Teacher/administrator web viewing and analysis | [Verified / Pending evaluation] | Synced classes, results, and item analysis (difficulty and discrimination) are available on the web portal. |
| FR-11 | Exam Day Board | [Verified / Pending evaluation] | Teachers can see missing, review, done, and absent students for a section and subject. |
| FR-12 | Student self-service results portal | Removed / out of scope | Students do not receive login accounts. Feedback is released by the teacher. |

**Interpretation.**  
The implemented modules match a teacher-first, offline-first workflow. The software is not a generic always-online platform and it is not a student information system. Exam-day work stays on the phone; the web portal organizes synchronized records afterward.

---

## 4.1.2 Non-Functional Requirements Verification

Non-functional characteristics were considered in relation to ISO/IEC 25010. Numeric means appear only in Section 4.4.1 after real forms are encoded.

- **Functional suitability.** The system performs exam preparation, OMR scanning, review, local storage, synchronization, and teacher-facing analysis as designed. Essay checking is outside scope.
- **Reliability.** After one approved sign-in and PIN setup, scanning and scoring continue from local storage if the network fails. Reliability still depends on device storage, correct print, and teacher review of flagged sheets.
- **Performance efficiency.** The system is intended to reduce repetitive manual checking by combining capture, scoring, and recording. Exact minutes saved are reported only if timed trials were recorded.
- **Usability.** Screens are arranged around teacher tasks (prepare, scan, review, sync). Perceived usability is reported through SUS only if SUS was administered.
- **Security.** Cloud access uses authenticated HTTPS/TLS. Offline PINs are hashed. Teachers see their own records; school administrators have approval and school-scoped oversight. Local roster and score data exist in SQLite for offline use and are **not** described as fully encrypted at rest.
- **Portability.** The mobile client is a Flutter application for Android and iOS. The web portal runs in a modern browser. Camera scanning requires a physical device.

**Interpretation.**  
The non-functional design supports exam-day continuity and later desk review. It does not claim that recognition is independent of print and lighting, or that local academic files are unreadable without a key.

---

## 4.2 System Features and Functionalities

The completed system has two teacher-facing environments and one shared backend.

### 4.2.1 Mobile Application Features

The mobile application is the exam-day tool. Its implemented features include:

- teacher registration, email verification, and sign-in;
- administrative approval before first productive use;
- offline PIN setup and unlock;
- Cloudflare Turnstile on login/registration when the school enables it;
- section and roster import or editing;
- answer-key editor with shared-key and section-only badges;
- print of standard and custom full-page portrait OMR sheets and OMR ID lists;
- live camera scanning and optional auto-capture;
- review of flagged, multi-mark, or low-confidence items before save;
- Exam Day Board (missing, review, done, absent);
- local SQLite storage of academic records;
- item analysis (difficulty and discrimination) on the device; and
- Sync Now (or later prompt) to the Laravel API when internet is available.

**Figure 4.1.** Mobile sign-in / PIN unlock  
*[Insert screenshot]*

**Figure 4.2.** Section roster and answer-key scope badges  
*[Insert screenshot]*

**Figure 4.3.** Scanner view with alignment guidance  
*[Insert screenshot]*

**Figure 4.4.** Review-before-save screen  
*[Insert screenshot]*

**Figure 4.5.** Exam Day Board  
*[Insert screenshot]*

**Figure 4.6.** Mobile item analysis  
*[Insert screenshot]*

### 4.2.2 Web Portal Features

The web portal is a synchronized desk companion. Scanning is not performed in the browser. Implemented features include:

- sign-in with the same teacher account used on the phone;
- **Classes** — sections, search, roster viewing and editing;
- **Prepare** — roster import, answer keys (including exam date, partial credit, multi-answer), print PDFs, OMR ID handouts;
- **Results** — synced scans, item analysis, CSV/PDF export; and
- **Admin** — access control and school overview for authorized administrators.

**Figure 4.7.** Web Classes  
*[Insert screenshot]*

**Figure 4.8.** Web Prepare (keys / print)  
*[Insert screenshot]*

**Figure 4.9.** Web Results / item analysis  
*[Insert screenshot]*

**Figure 4.10.** Admin access control  
*[Insert screenshot]*

The portal does not contain student login, student dashboards, or a web camera scanner.

---

## 4.3 System Architecture and Design

The system follows a hybrid offline-first client-server architecture. The mobile client performs local scanning and storage. The cloud layer provides authentication, teacher-owned backup, and synchronized access for the web portal.

### 4.3.1 Mobile Client Layer

The mobile application was built with Flutter (Dart SDK 3.x-compatible). The scanning engine uses native OpenCV on Android and iOS. Local records are stored in SQLite so grading can continue without a network session.

### 4.3.2 Backend and Synchronization Layer

The backend is Laravel 11 with Sanctum personal-access tokens on PHP 8.2+. It handles registration, login, email verification, password reset, teacher approval, and sync endpoints for sections, students, subjects (answer keys), scan results, and related records. Production data are stored in PostgreSQL. SQLite may be used in development.

### 4.3.3 Web Portal Layer

The web component is a Next.js / React / TypeScript application. It provides synchronized access to classes, answer keys, printable materials, results, and analysis for teachers and authorized administrators.

### 4.3.4 Database Structure

| Store | Technology | Contents |
|-------|------------|----------|
| On-device | SQLite | Roster, keys, scores, sync flags; photos in local files |
| Server (production) | PostgreSQL | Teacher accounts, approval status, synchronized academic rows |
| Server (development) | SQLite | Same schema for local API testing |

**Figure 4.11.** System architecture (Flutter + native OpenCV + SQLite ↔ Laravel API ↔ PostgreSQL ↔ Next.js)  
*[Insert diagram matching the real stack]*

**Figure 4.12.** Use-case diagram (Teacher, School Administrator)  
*[Insert; do not include a Student-portal actor]*

**Figure 4.13.** Entity-relationship diagram of synchronized entities  
*[Insert: users/teachers, sections, students, subjects/keys, scan_results]*

This arrangement reflects the offline-first rule: write locally first, synchronize later, keep photographs off the server.

---

## 4.4 System Evaluation

This section may contain **only** data the researchers actually gathered. If a questionnaire, timing study, or accuracy trial was not finished, keep the heading and write that the instrument is pending—or remove the numeric table.

### 4.4.1 ISO/IEC 25010 Software Quality Assessment

The developed system was evaluated using selected ISO/IEC 25010 characteristics.

- Respondents: `[Insert actual count and role — instructors / administrators]`
- Instrument: ISO/IEC 25010 questionnaire
- Scale: `[Insert, e.g., 5-point Likert]`

**Table 4.3.** Mean scores for ISO/IEC 25010 characteristics

| Quality characteristic | Mean score | Qualitative interpretation |
|------------------------|-----------:|----------------------------|
| Functional suitability | [Insert] | [Insert] |
| Reliability | [Insert] | [Insert] |
| Performance efficiency | [Insert] | [Insert] |
| Usability | [Insert] | [Insert] |
| Security | [Insert] | [Insert] |
| Portability | [Insert] | [Insert] |
| **Overall mean** | **[Insert]** | **[Insert]** |

**Interpretation.**  
Based on the accomplished ISO/IEC 25010 evaluation, the respondents rated the developed system as `[Insert official verbal interpretation used by your college]`. This rating refers to instructor experience with the offline-first OMR workflow, review tools, synchronization, and teacher-facing interfaces. It is not a laboratory accuracy percentage.

If forms are not yet encoded, use:

> ISO/IEC 25010 forms were prepared for instructor evaluation. Computed means will be inserted here after encoding. No substitute scores are reported.

### 4.4.2 Functionality Testing Summary

Testing evidence may include automated repository tests, integration checks, and classroom walkthroughs. Report only logged totals.

**Table 4.4.** Summary of functional tests

| Testing level | Total tests | Passed | Failed | Pass rate |
|---------------|------------:|-------:|-------:|----------:|
| Unit testing | [Insert] | [Insert] | [Insert] | [Insert] |
| Integration testing | [Insert] | [Insert] | [Insert] | [Insert] |
| System / acceptance walkthroughs | [Insert] | [Insert] | [Insert] | [Insert] |
| **Total** | **[Insert]** | **[Insert]** | **[Insert]** | **[Insert]** |

**Interpretation.**  
[Insert.] Suggested pattern after real numbers exist:

> Functional testing covered authentication, local storage, answer-key management, OMR scanning, scan review, synchronization, and web access to synced records. Failures, if any, were `[describe honestly]`.

Do not write “100% pass rate” unless the log shows zero failures.

### 4.4.3 System Usability Scale (SUS) Results

Include this subsection only if SUS questionnaires were completed.

- Respondents: `[Insert count; instructors only unless you have a documented non-portal student instrument]`
- Calculated SUS score: `[Insert]`
- Adjective rating: `[Insert, using the standard SUS adjective scale]`
- Acceptability: `[Insert]`

**Interpretation.**  
The SUS result indicates that the developed system was perceived as `[Insert]` by the evaluation respondents. This score describes ease of use of the teacher mobile and web workflows. It does not measure bubble-recognition accuracy.

If SUS was not administered, write:

> A System Usability Scale instrument is part of the evaluation plan. No SUS score is reported in this draft because completed forms have not been computed.

### 4.4.4 Optical Mark Recognition Validation

If—and only if—you compared printed sample sheets with manual keys, report that trial here.

**Table 4.5.** Sample-sheet comparison with manual scoring *(optional; omit if not done)*

| Trial condition | Sheets / items | Agreements | Disagreements | Notes |
|-----------------|----------------:|-----------:|--------------:|-------|
| [Printer, paper, light] | [Insert] | [Insert] | [Insert] | [Insert] |

State the printer, scale (must be 100% / actual size), pencil/pen type, and whether review was used. Do **not** insert 99.76% or any other literature figure as if it were this trial.

If `SCAN_VALIDATION.md` was followed but not quantified, say so:

> Printed-sheet validation was performed as a qualitative checklist (alignment marks visible, sample scans accepted after review). A numeric accuracy rate is not claimed in this chapter.

### 4.4.5 Operational Impact Discussion

The manual and automated workflows may be compared in words. Timed or percentage gains appear only if you measured them.

Safe statements that match the implementation:

- The system removes repeated hand-tallying of bubbles once a sheet is successfully read and reviewed.
- Scores can be stored immediately on the device even when Wi-Fi is down.
- Teachers do not depend on continuous internet during the scanning session after PIN unlock.
- Synchronized records reduce re-typing of the same scores onto a separate spreadsheet, provided the teacher syncs later.
- Item analysis gives a structured view of difficulty and discrimination that is easy to lose in purely manual checking.
- Advertisement interruptions from free third-party scanners are not present in this application.

Unsafe unless measured:

- “88% faster,” “75% less friction,” “processing time dropped from 25 minutes to 3 minutes,” or any figure copied from another project’s Chapter 4.

---

## 4.5 Discussion of Results

The findings available from the implemented system, independent of unfinished questionnaires, are as follows.

The architecture matches the problem stated in Chapter 1. Instructors can prepare materials, scan, and score without keeping a browser session alive. The offline model is not “never online.” It is **bootstrap once, then exam-day offline, then sync when convenient**. That distinction matters on a new phone or for a newly approved teacher.

The review-before-save step is a deliberate limit on full automation. The engine can misread a poorly printed or lightly shaded sheet. Requiring review on flagged and auto-captured sheets reduces the chance that a doubtful reading becomes a final grade without a teacher looking at it.

Shared versus section-only keys address a data-integrity risk that generic OMR apps often leave implicit. When several sections take the same quiz, one shared key is appropriate. When two sections use the same subject name but different answers, a section-only key and the corresponding print/scan labels reduce cross-grading.

The web portal extends the phone, it does not replace it. Larger-screen review of item analysis is useful after sync. It is not a student portal and should not be defended as one.

Honest operational limits remain:

- print scale and toner quality;
- lighting and camera shake;
- incomplete or multiple shading;
- custom-sheet capacity limits (option count versus item count);
- multiple-choice only;
- local academic data stored for offline use; and
- no automatic release of results to a student account.

These limits are consistent with the related studies in Chapter 2, which also reported print and shading sensitivity. They are not treated as defects that the paper hides.

`[Insert additional discussion after ISO/SUS/accuracy numbers exist. Interpret those numbers; do not upgrade them into guarantees.]`

---

## 4.6 Summary of Findings

Based on the **actual** developed system, and pending insertion of computed evaluation scores, the study finds that:

1. The system implements an offline-first, teacher-side OMR scanning and grading workflow with local SQLite storage.
2. Daily offline use follows one online registration or sign-in, verification, administrative approval, and PIN setup.
3. Native OpenCV on Android and iOS reads printed sheets; flagged readings can be reviewed before save.
4. Answer keys may be shared across sections or restricted to one section; custom layouts are full-page portrait only.
5. Records synchronize through a Laravel 11 API to PostgreSQL; scan photographs are not uploaded.
6. The Next.js web portal is a teacher and administrator companion for classes, preparation, results, and item analysis. It is not a student login portal.
7. The system is limited to objective items and remains sensitive to print, lighting, and shading.
8. ISO/IEC 25010, SUS, timed efficiency, and numeric accuracy findings will be stated only from completed instruments: `[Insert final verbal summary after data encoding]`.

---

## Manuscript checklist before printing Chapter 4

- [ ] Every `[Insert …]` is replaced or the subsection is deleted.
- [ ] No booking, dispatch, heatmap, or “field worker” sentences remain.
- [ ] No student-portal screenshot is labeled as a finished feature.
- [ ] Architecture diagram shows Flutter, native OpenCV, SQLite, Laravel, PostgreSQL, Next.js.
- [ ] Security wording says HTTPS/TLS + hashed PIN + local photos—not “no unencrypted student data on the phone.”
- [ ] Literature accuracy (e.g., 99.76%) does not appear as a product result.
- [ ] Screenshots are from the current app build, not discarded mockups.
