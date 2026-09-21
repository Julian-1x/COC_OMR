# Paper-System Alignment Guide

This guide aligns the research paper to the **actual COC OMR system** in this repository.

The rule for revisions is:

- **The system is the source of truth**
- **The paper must adjust to the system**
- **Do not add claims that the software does not currently support**
- **Do not invent evaluation numbers, user counts, or performance metrics**

## Executive Summary

The current PDFs are **not fully aligned** with the system.

There are two levels of issues:

1. **Chapter 1 to 3** is partly usable, but several claims are outdated or too broad.
2. **Chapter 4 is critically wrong** and appears to be copied from a different project about booking, scheduling, field workers, proof uploads, and geospatial analysis. It must be **rewritten from scratch** for the OMR system.

## What the system actually is

Based on the current repository:

- **Mobile app:** Flutter
- **Core purpose:** offline-first OMR scanning and grading for teachers
- **Scanning:** native OpenCV on Android and iOS
- **Local storage:** SQLite on device
- **Cloud/backend:** Laravel 11 API with Sanctum
- **Web portal:** teacher/admin desk portal built with Next.js/React
- **Central production database:** PostgreSQL in production, SQLite for dev is supported
- **Primary users:** teachers; school admins have read/approval functions
- **Offline model:** one online sign-in first, then daily unlock with an offline PIN
- **Cloud sync:** roster, answer keys, scan results, deadlines, etc.
- **Scan photos:** local on device only, not uploaded to the cloud

Key repo references:

- `README.md`
- `PRODUCTION.md`
- `PRIVACY.md`
- `coc-omr-api/README.md`
- `omr_web/README.md`

## Safe claims you can keep

These are consistent with the system and can stay, with wording cleanup:

- The system is **offline-first**
- The system supports **mobile OMR scanning using a phone camera**
- The system uses **OpenCV-based image processing**
- The system stores data locally using **SQLite**
- The system can **sync results and records to a web server later**
- The system provides **item analysis** and class/result views
- The system is designed to reduce dependence on continuous internet
- The system is intended for **objective / multiple-choice assessments**
- The system includes **authentication** and **role-aware access**

## Claims that must be corrected

### 1. Student web portal access

Current paper claim:

- students use the web portal to view results and analytics

Actual system:

- the web portal is described as a **teacher web portal**
- school admins have separate read/approval views
- there is no clear evidence in the current repo that a dedicated student-facing result portal is the finished production workflow

Safe replacement:

- “The web component provides a desk companion portal for teachers and authorized school administrators to manage synchronized classes, answer keys, printable sheets, and assessment results.”

If you want to mention students at all:

- only mention them as **beneficiaries of faster and more reliable result processing**, not as direct portal users, unless you have a working deployed student portal that you can demonstrate.

### 2. Central database is MySQL

Current paper claim:

- central database is MySQL

Actual system:

- production docs say **PostgreSQL**
- Laravel API also supports SQLite for development

Safe replacement:

- “The central server uses Laravel 11 and a relational database, with PostgreSQL used for production deployment and SQLite supported for development/testing.”

### 3. Web stack is HTML + Vanilla JS

Current paper claim:

- web dashboard uses HTML and vanilla JS

Actual system:

- `omr_web` is a **Next.js / React** application

Safe replacement:

- “The web portal is implemented using a modern React-based framework (Next.js) for teacher/admin access to synchronized academic data.”

### 4. Backend is generic PHP 10+

Current paper claim:

- backend: PHP 10+

Actual system:

- backend is **Laravel 11**
- PHP requirement is **8.2+**

Safe replacement:

- “The backend is implemented using Laravel 11 on PHP 8.2+, with Sanctum-based token authentication.”

### 5. Flutter version is `0.72+`

Current paper claim:

- Flutter 0.72+

Actual system:

- invalid / clearly wrong for current Flutter tooling

Safe replacement:

- “The mobile application is built with Flutter and Dart SDK 3.x-compatible tooling.”

### 6. OpenCV package wording

Current paper claim:

- `react-native-opencv`

Actual system:

- not React Native
- Flutter app uses native Android/iOS bridges for OpenCV

Safe replacement:

- “The scanning engine uses native OpenCV integration on Android and iOS, bridged into the Flutter application.”

### 7. “No sensitive student information is stored unencrypted on mobile devices”

Current paper claim:

- too strong and risky

Actual system:

- `PRIVACY.md` says student names, rosters, scores, and answers are stored on the phone
- offline PIN is hashed
- scan photos remain local

Safe replacement:

- “The mobile application stores roster and assessment records locally to support offline operation. The offline PIN is stored as a hash, and scan photos remain on the device only. Cloud synchronization uses authenticated API access over HTTPS/TLS.”

Do **not** claim full at-rest encryption for all local academic data unless you actually implemented it and can prove it.

### 8. “Grade encryption during synchronization”

Current paper claim:

- grade encryption during synchronization

Actual system:

- the safe documented claim is **HTTPS/TLS transport security**

Safe replacement:

- “Synchronized records are transmitted through authenticated HTTPS/TLS connections.”

### 9. “Only standard OMR layouts”

Current paper claim:

- system supports standard OMR layouts only

Actual system:

- system now supports **custom portrait full-page layouts** in addition to standard presets
- half/quarter and landscape are no longer offered for new layouts

Safe replacement:

- “The system supports fixed standard OMR layouts and scan-safe custom full-page portrait layouts defined within the application.”

### 10. Scope limited to Engineering only

Current paper claim:

- system is strictly for the Department of Engineering

Actual system:

- codebase and docs are now broader for **Cagayan de Oro College teachers**
- if your study locale/respondents are Engineering, that is fine, but the software itself is no longer engineering-only

Safe replacement:

- “The study locale and initial evaluation focus on the Department of Engineering; however, the implemented system architecture is extensible to other sections and departments within the institution.”

## Chapter 1 to 3 revision checklist

## Chapter 1

### Introduction

Keep:

- manual checking is slow
- offline-first rationale
- need for analytics and faster grading

Soften or revise:

- do **not** overstate that existing competitor apps require constant internet unless your source clearly proves that exact claim
- better to say:
  - “existing tools may introduce workflow interruptions, free-tier limits, and dependence on online services for some functions”

### Statement of the Problem

Good general direction, but refine to match the built system:

- offline reliability
- ad-free teacher-owned workflow
- local-first scanning and grading
- later synchronization
- result analysis for teachers/admins

### Scope and Limitations

Replace with something closer to:

- mobile app for teachers to scan, review, and grade multiple-choice exams
- web portal for teachers/admins to manage synchronized academic data and view summaries/results
- objective tests only
- scan accuracy depends on print quality, lighting, shading, and correct framing
- custom layouts are limited to scan-safe configurations defined by the app
- online sign-in is required at least once before offline PIN-based daily use

## Chapter 2

Mostly literature framing, but clean up:

- remove weak or overstated claims you cannot support
- keep the digital-divide and offline-first argument
- keep OMR/OpenCV feasibility literature
- keep analytics gap argument
- avoid implying your system has “AI scanning” unless you explicitly implemented and documented AI/ML models

## Chapter 3

### Research Design / Locale / Respondents

These can stay if they describe the study process truthfully.

### Functional Requirements section

Revise requirements to match real modules:

- teacher registration/sign-in
- offline PIN unlock
- section and roster management
- answer key creation and editing
- standard and custom sheet printing
- OMR ID linking
- scan review and flagged-sheet checking
- offline local storage
- cloud sync to Laravel API
- teacher/admin web viewing and management
- item analysis and export features

### Database Design

Correct to:

- local mobile database: SQLite
- central server database: PostgreSQL in production, SQLite possible in dev

### UI design section

Replace generic “students can view results via web dashboard” wording with:

- teachers use the phone app for scanning
- teachers and authorized admins use the web portal for synchronized data review and preparation

### Technology Stack

Replace the current table with a truthful one:

- Mobile App: Flutter, Dart SDK 3.x-compatible
- OMR Engine: native OpenCV on Android and iOS
- Local DB: SQLite
- Backend/API: Laravel 11, PHP 8.2+, Sanctum
- Web Portal: Next.js, React, TypeScript
- Central DB: PostgreSQL (production), SQLite (development/testing)

## Chapter 4 is not usable

`CHAPTER-4_FINAL.pdf` is from a different system.

These are obvious false mismatches:

- booking and scheduling
- workload-balanced personnel assignment
- field task sync
- proof photo uploads for field workers
- geospatial service density heatmap
- promo management
- customers and field technicians
- operational transactions dropping from 25–30 minutes to 3 minutes

None of those are the COC OMR system.

This chapter must be **discarded and rewritten**.

## Safe Chapter 4 structure to use

Below is a safe replacement structure that matches the actual system. Use your **real evaluation data** where indicated.

## 4.1 System Requirements Analysis

Discuss that the finished system was checked against its actual requirements:

- teacher authentication and access
- offline PIN setup and unlock
- section and roster management
- answer key management
- OMR sheet printing
- mobile scanning and grading
- review of flagged/low-confidence scans
- local data storage
- synchronization to server
- teacher/admin web access to synchronized data
- item analysis and exports

## 4.1.1 Functional Requirements Verification Matrix

Use modules like these instead of the fake ones in the PDF:

| Module ID | Functional Requirement | Verification Status | Operational Outcome |
|-----------|------------------------|---------------------|---------------------|
| FR-01 | User authentication | Verified | Teachers can register/sign in; protected data stays account-scoped |
| FR-02 | Offline PIN unlock | Verified | Teachers can reopen the app offline after initial online sign-in |
| FR-03 | Roster management | Verified | Teachers can import/manage class rosters |
| FR-04 | Answer key management | Verified | Teachers can create/edit answer keys by subject/section |
| FR-05 | OMR sheet generation | Verified | Printable answer sheets and OMR IDs can be generated |
| FR-06 | Mobile OMR scanning | Verified | Answer sheets can be captured and processed using the phone camera |
| FR-07 | Scan review flow | Verified | Risky or ambiguous scans can be reviewed before final save |
| FR-08 | Local offline storage | Verified | Records persist locally through SQLite |
| FR-09 | Synchronization | Verified | Local data can be uploaded later through the Laravel API |
| FR-10 | Web results/analysis | Verified | Synced data can be viewed in the teacher/admin portal |

Do **not** write “100% verified via automated logs” unless you actually documented that method.

## 4.1.2 Non-Functional Requirements Verification

Keep this qualitative and truthful:

- Functional suitability: system performs scanning, grading, storage, sync, and analytics as designed
- Reliability: supports offline-first operation and later synchronization
- Performance efficiency: intended to reduce manual checking time
- Usability: evaluated through SUS and user observation, if you truly conducted this
- Security: authenticated access, hashed PIN, HTTPS/TLS, teacher-owned data scope
- Portability: mobile app on Android/iOS; web portal in modern browsers

## 4.2 System Features and Functionalities

Split it correctly:

### 4.2.1 Mobile Application Features

- teacher sign-in and offline PIN
- roster and section handling
- answer key setup
- standard/custom sheet printing
- live OMR scanning
- scan review for flagged sheets
- local storage and sync

### 4.2.2 Web Portal Features

- teacher sign-in
- classes and roster views
- prepare tools (answer keys, print sheets, OMR IDs)
- results and item analysis
- admin oversight/access approval where applicable

## 4.3 System Architecture and Design

Use actual architecture:

- Flutter mobile client
- native OpenCV scan engine on Android/iOS
- SQLite local database
- Laravel API for authentication and sync
- Next.js web portal
- PostgreSQL production database

Do not mention:

- scheduling engine
- field workers
- dispatch
- customers
- geospatial heatmaps

## 4.4 System Evaluation

Only include numbers you really collected.

If you do not yet have finalized real metrics, use placeholders while drafting:

- `[Insert actual ISO/IEC 25010 respondent count]`
- `[Insert actual SUS score]`
- `[Insert actual unit/integration/system testing totals]`
- `[Insert actual OMR accuracy or comparison results if you measured them]`

Do not keep the current numbers from the PDF unless they truly came from your OMR study.

## 4.4.1 ISO/IEC 25010

If you conducted this, present your real means.

If not finalized, write:

- “The completed system was evaluated using ISO/IEC 25010 criteria. Final computed mean scores for each criterion will be presented based on the accomplished respondent evaluation forms.”

## 4.4.2 Functionality Testing Summary

This can be grounded partly in the repo:

- the codebase includes automated tests for answer keys, scan identity, layout scannability, session layout, item analysis, imports, sync-related behavior, and other core modules

But do not invent a final numeric table unless you are using your actual documented test totals.

## 4.4.3 SUS Results

Only include a SUS score if you computed it from real forms.

## 4.4.4 Operational Comparison

You may compare manual vs. automated workflow, but avoid invented percentages like:

- “88% throughput acceleration”
- “75% workflow friction reduction”

unless those were measured and documented.

Safer wording:

- “The developed system reduced manual checking steps by consolidating scanning, scoring, local storage, and later synchronization into a single workflow.”

## 4.5 Discussion of Results

This section should discuss:

- offline-first grading value
- reduction of exam-day dependence on internet
- faster checking workflow versus manual checking
- value of item analysis and synchronized records
- need for scan validation under real lighting/printing conditions

## 4.6 Summary of Findings

Use a safe conclusion pattern like:

1. The developed system successfully implements offline-first OMR scanning and grading.
2. The system supports local storage and later synchronization to a centralized server.
3. The system provides teacher-facing preparation and result-review functions through mobile and web components.
4. The system is limited to objective-type assessments and depends on proper printing, shading, and scan conditions.
5. Final usability and software quality findings must reflect actual accomplished evaluation data only.

## Recommended title adjustment

Your current title is usable, but if you want it tighter and closer to the real product:

**Hybrid Offline-First OMR Scanning System with Teacher Web Synchronization and Analytics for Cagayan de Oro College**

Why this is safer:

- removes the overclaim that the web is mainly for students
- matches the teacher/admin portal reality
- avoids locking the software identity too narrowly if the app is now broader than Engineering

If your panel requires the Department of Engineering to remain explicit, use:

**Hybrid Offline-First OMR Scanning System with Teacher Web Synchronization and Analytics for the Department of Engineering of Cagayan de Oro College**

## Most important corrections before defense

If you only fix the highest-risk issues, fix these first:

1. **Replace Chapter 4 completely**
2. **Change MySQL to PostgreSQL/Laravel production wording**
3. **Change HTML/Vanilla JS to Next.js/React web portal**
4. **Remove or soften student-portal claims**
5. **Fix security wording so it does not overclaim encryption**
6. **Update technology stack and architecture**
7. **Update scope to mention current custom sheet support and offline PIN**

## Defensibility rule

During defense, every claim in the paper should pass this test:

> “Can we open the system or the code and show this is true right now?”

If not, rewrite or remove it.
