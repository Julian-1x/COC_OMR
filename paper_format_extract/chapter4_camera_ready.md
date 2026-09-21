# CHAPTER 4
## PRESENTATION, ANALYSIS, AND INTERPRETATION OF DATA

This chapter presents the empirical results, systematic analysis, and qualitative interpretation of the data gathered during the testing and evaluation of the developed **Hybrid Offline-First Optical Mark Recognition (OMR) Scanning System with Web-Based Grade Synchronization and Analytics**. The findings are structured to address the system requirements, technical architecture, and software quality performance in line with the capstone evaluation metrics and the Master Testing Registry used for this study.

The discussion is limited to the completed system: a Flutter mobile application for teacher-side scanning and grading, a Laravel 11 backend for authentication and synchronization, and a Next.js web portal for synchronized academic preparation and result analysis. Claims that cannot be demonstrated in the running software or in completed evaluation forms are omitted.

## 4.1 SYSTEM REQUIREMENTS ANALYSIS

The foundational phase of evaluating the developed system involves a rigorous, retrospective verification of both its functional and non-functional requirements. This process ensures that the software engineering output aligns with the specifications gathered during instructor consultation and requirements elicitation (Chapter 3).

To bridge the gap between the organizational problems stated in Chapter 1 and the final software artifact, the system was subjected to systematic black-box testing, requirements mapping, and operational verification. Verification focused on the modules that exist in the software: teacher authentication and approval, offline PIN unlock, roster and answer-key management (including shared and section-only keys), printable standard and custom full-page sheets, camera-based OMR scanning with review-before-save, local SQLite storage, later API synchronization, and teacher/administrator web viewing of synchronized records.

The completed system addresses the grading problems identified in Chapter 1 by allowing instructors to prepare class records, scan answer sheets on a mobile device, review flagged readings, save results locally without continuous internet access, and synchronize academic records later. This structure supports exam-day operation when campus connectivity is unstable. It does not provide a student login portal.

### Table 4.1 Level 1 - Unit Testing

Unit testing examined individual functions and services in isolation, following Series 100 of the Master Unit Testing Registry (authentication, security, formatting, and session rules) as adapted for COC OMR.

**Table 4.1.** Level 1 - Unit Testing (Series 100 registry cases)

| Unit ID | Target function / code | Testing scenario profile | Expected isolation output | Result |
|---------|------------------------|--------------------------|---------------------------|--------|
| UT-101 | Laravel `email` rule; Flutter email validation | Structural typos (`test@com`, `@@domain.com`, blank) | Rejected; valid-email message | Passed |
| UT-102 | Password rules (Dart/TS) + Laravel `Password::defaults()` | Short or incomplete passwords | Rejected on register/reset | Passed |
| UT-103 | Laravel `Hash::make()` (bcrypt) | New teacher password at registration | Unique salted hash; plain text not stored | Passed |
| UT-104 | Laravel `Auth::attempt()` | Correct vs wrong password | Match returns true; mismatch fails login | Passed |
| UT-105 | Sanctum `createToken()` (Bearer token, not JWT) | Successful login (web / mobile device name) | Personal access token returned | Passed |
| UT-106 | Web session max age; app token until revoke | Web cookie after expiry window | Web requires re-login; app token until sign-out/revoke | Passed |
| UT-107 | `PersonName.normalize()` (PHP/Dart/TS) | Mixed case, surname-first, extra spaces | Clean First Last format | Passed |

In addition to the registry cases above, automated unit and contract tests in the project repositories cover answer-key scope, item-analysis calculations, roster import rules, layout/scannability contracts, scan-confidence classification, and related services.

**Table 4.1a.** Automated unit-test execution log (repository)

| Testing level | Total tests | Passed | Failed | Pass rate |
|---------------|------------:|-------:|-------:|----------:|
| Flutter unit / widget (`flutter test`) | 242 | 242 | 0 | 100% |
| Web unit (Vitest, `omr_web`) | 52 | 52 | 0 | 100% |
| Combined automated unit suite | 294 | 294 | 0 | 100% |

**Interpretation.**  
Unit tests were used to check isolated authentication, naming, scoring, layout, and data rules before classroom demonstration. The registry Series 100 cases (UT-101 to UT-107) and the combined automated suite (294/294) support internal consistency. These tests do not replace printed-sheet accuracy trials under ordinary classroom lighting.

### Table 4.1.1 Level 2 - Integration Testing

Integration testing examined the data-sharing bridges among the mobile client, local SQLite database, Laravel API, and web portal, following Series 100 of the Master Integration Testing Registry as mapped to COC OMR.

**Table 4.1.1.** Level 2 - Integration Testing

| Integration ID | Interoperating subsystems | Testing scenario profile | Expected cross-module behavior | Result |
|----------------|---------------------------|--------------------------|--------------------------------|--------|
| IT-101 | Register UI - RegisterController | Teacher submits name, `@phinmaed.com` email, COC department, password | POST register; name normalized; pending admin approval; verification email | Passed |
| IT-102 | Login UI - session storage - LoginController | Approved teacher signs in | Sanctum token returned; web `coc_api_token` cookie; app stores credentials and supports offline PIN setup | Passed |
| IT-103 | Results/Classes search - client filter | Partial name or OMR ID typed | Local grid filter without full page reload | Passed |
| IT-104 | Roster import - import service - StudentSyncController | CSV/Excel class list uploaded | Parsed client-side; JSON sync to API (not multipart image upload) | Passed |

**Additional integration paths verified during system walkthroughs**

| Integration path | Result | Notes |
|------------------|--------|-------|
| Mobile application - local SQLite | Passed | Offline save of roster, keys, and scores |
| Mobile application - Laravel API (sync) | Passed | Upload/download of sections, students, subjects, scan results |
| Web portal - Laravel API | Passed | Classes, Prepare, Results, Admin |
| Scan photos uploaded to server | Not applicable | Photos remain on the device by design |

**Interpretation.**  
Integration checks confirmed that records written on the phone can later appear in the teacher web portal after a successful sync. Scan photographs are excluded from synchronization, which matches the privacy design of the system. Integration IDs IT-101 to IT-104 follow the testing-plan bridge pattern (frontend - API) with COC OMR-specific payloads and endpoints.

### Level 3 - System Testing

System testing exercised complete teacher workflows rather than single functions. Cases follow Series 100-500 of the Master System Testing Registry as adapted for COC OMR.

**Table 4.1.2.** Level 3 - System Testing (Series 100: Authentication and access)

| System Test ID | Module | Expected system response | Result |
|----------------|--------|--------------------------|--------|
| ST-101 | Account registration | Duplicate pending email shows waiting-for-approval guidance; approved duplicate directs to Login | Passed |
| ST-102 | Login security | Wrong password fails; clear credentials error | Passed |
| ST-103 | Password masking | Password field masked | Passed |
| ST-104 | Form validation | Blank required fields blocked with inline errors | Passed |
| ST-105 | Role-based access | Non-admin cannot use Admin desk | Passed |
| ST-106 | Session logout | After logout, protected pages require re-login | Passed |

**Table 4.1.3.** Level 3 - System Testing (Series 200: Roster, keys, and CRUD)

| System Test ID | Module | Expected system response | Result |
|----------------|--------|--------------------------|--------|
| ST-201 | Roster creation / import | Valid CSV/Excel import creates sections and students | Passed |
| ST-202 | Input boundaries | Invalid numeric answer-key fields rejected | Passed |
| ST-203 | Record modification | Edited student name persists after sync | Passed |
| ST-204 | Record removal | Student removed only after confirmation | Passed |
| ST-205 | Large result lists | Results load; client-side filter works | Passed |

**Table 4.1.4.** Level 3 - System Testing (Series 300-500: Search, exports, sync)

| System Test ID | Module | Expected system response | Result |
|----------------|--------|--------------------------|--------|
| ST-301 | Text search | Matching name / OMR ID rows shown | Passed |
| ST-302 | Empty search | Clear "no matching records" state | Passed |
| ST-303 | Multi-filter | Section/subject filters apply to results and analysis | Passed |
| ST-402 | PDF export / print | Valid OMR or results PDF; print at 100% scale | Passed |
| ST-403 | Spreadsheet export | CSV opens correctly | Passed |
| ST-501 | UI feedback / API wake | Connecting message and retries; no false account error | Passed |
| ST-502 | Settings profiling | Account and Sync Now visible when online | Passed |
| ST-503 | Offline then sync | Local scans preserved; cloud updated after Sync Now | Passed |

End-to-end exam-day scenarios exercised together with the registry cases above:

| End-to-end scenario | Result | Notes |
|---------------------|--------|-------|
| Register - verify email - admin approve - set PIN | Passed | Online bootstrap required once |
| Unlock offline with PIN and open a section | Passed | No Wi-Fi required after bootstrap |
| Create shared or section-only answer key and print sheets | Passed | Full-page portrait; 100% print scale |
| Scan sample sheets - review flags - save scores | Passed | Review required for risky / auto-capture scans |
| View Exam Day Board (missing / review / done / absent) | Passed | Mobile only |
| Sync when online - view results and item analysis on web | Passed | Teacher/admin portal |
| Student logs in to view personal results | Out of scope | No student portal in the implemented system |

**Interpretation.**  
System testing followed the real exam-day path: prepare, print, scan, review, store locally, and sync later. The web portal was verified as a teacher/administrator companion, not as a scanning station and not as a student portal. ST-401 (numeric sample-sheet accuracy against a fixed agreement threshold) is reported separately in Section 4.4.4 only when a quantified printed-sheet trial is logged; it is not treated as automatically passed by registry membership alone.

## 4.1.1 FUNCTIONAL REQUIREMENTS VERIFICATION MATRIX

Functional requirements define the core operational tasks, data manipulation, and localized modules that the system must execute for instructors. Rather than merely confirming that the software "works," this section tracks each requirement against its technical verification and operational outcome.

**Table 4.2.** Requirements traceability and functional verification matrix

| Module ID | Target functional requirement | Technical verification status | Operational outcome |
|-----------|-------------------------------|-------------------------------|---------------------|
| FR-01 | Authorized teachers can register, verify email, and sign in | Verified (ST-101-ST-104; IT-101-IT-102) | The same account is used on mobile and web. New teachers remain pending until a school administrator approves them. |
| FR-02 | Offline unlock after initial account setup | Verified (end-to-end PIN unlock; ST-503) | Teachers can reopen the app with a hashed offline PIN without internet. |
| FR-03 | Section and roster management | Verified (ST-201-ST-204; IT-104) | Teachers can create or sync sections and maintain student names, school IDs, and OMR IDs. |
| FR-04 | Answer-key creation, including shared and section-only keys | Verified (ST-202; automated answer-key scope tests) | Keys can be limited to one section or shared across linked sections. Partial credit is available for multi-answer items. |
| FR-05 | Generation of printable OMR materials | Verified (ST-402; print walkthroughs) | Standard 30-100 sheets, scan-safe custom full-page portrait sheets, and OMR ID lists can be printed. |
| FR-06 | Camera-based OMR processing using OpenCV | Verified (scan walkthroughs; review path) | The phone captures the sheet; native OpenCV on Android/iOS reads marks against the printed layout contract. |
| FR-07 | Review of risky or ambiguous scans | Verified (scan review walkthroughs; confidence classification tests) | Flagged, low-confidence, or multi-mark items can be inspected before the score is saved. Auto-capture requires review. |
| FR-08 | Local storage during offline operation | Verified (SQLite integration; ST-503) | Roster, keys, and scores persist in SQLite. Scan photos stay on the device. |
| FR-09 | Synchronization of records when connectivity is available | Verified (IT-102/IT-104; ST-502-ST-503) | Teachers upload/download academic records through the Laravel API over HTTPS. Photos are not synced. |
| FR-10 | Teacher/administrator web viewing and analysis | Verified (web - API integration; ST-301-ST-303) | Synced classes, results, and item analysis (difficulty and discrimination) are available on the web portal. |
| FR-11 | Exam Day Board | Verified (mobile walkthrough) | Teachers can see missing, review, done, and absent students for a section and subject. |
| FR-12 | Student self-service results portal | Removed / out of scope | Students do not receive login accounts. Feedback is released by the teacher. |

**Interpretation.**  
The implemented modules match a teacher-first, offline-first workflow. The software is not a generic always-online platform and it is not a student information system. Exam-day work stays on the phone; the web portal organizes synchronized records afterward.

## 4.1.2 NON-FUNCTIONAL REQUIREMENTS VERIFICATION

Non-functional characteristics were considered in relation to ISO/IEC 25010. Numeric mean scores appear only in Section 4.4.1 after real forms are encoded.

- **Security.** Cloud access uses authenticated HTTPS/TLS and Laravel Sanctum tokens. Offline PINs are hashed. Teachers see their own records; school administrators have approval and school-scoped oversight. Role gates block non-admin access to the Admin desk (ST-105). Local roster and score data exist in SQLite for offline use and are **not** described as fully encrypted at rest. Data handling is aligned with the Data Privacy Act of 2012 (RA 10173) through account scoping, transport security, and keeping scan photographs on the device.
- **Performance efficiency.** Page transitions, sync requests, and scan processing are intended to remain practical under classroom multi-user conditions. Exact seconds-per-sheet or minutes-saved are reported only if timed trials were recorded.
- **Portability.** The administrative and teacher web portal functions across modern browsers (Chrome/Edge). The mobile client is a Flutter application for Android and iOS; camera scanning requires a physical device.
- **Reliability.** After one approved sign-in and PIN setup, scanning and scoring continue from local storage if the network fails (ST-503). Reliability still depends on device storage, correct print, and teacher review of flagged sheets.
- **Usability.** Screens are arranged around teacher tasks (prepare, scan, review, sync). Perceived usability is reported through SUS only if SUS was administered (Section 4.4.3).
- **Functional suitability.** The system performs exam preparation, OMR scanning, review, local storage, synchronization, and teacher-facing analysis as designed. Essay checking is outside scope.

**Interpretation.**  
The non-functional design supports exam-day continuity and later desk review. It does not claim that recognition is independent of print and lighting, or that local academic files are unreadable without a key.

## 4.2 SYSTEM FEATURES AND FUNCTIONALITIES

The completed software delivers a unified environment that connects a teacher mobile application with a teacher/administrator web portal through a shared Laravel API. Features were demonstrated to respondents before formal evaluation and are divided into two main interfaces.

### 4.2.1 Mobile Application Features

The mobile application is the exam-day tool. Implemented features include:

- teacher registration, email verification, and sign-in;
- administrative approval before first productive use;
- offline PIN setup and unlock;
- Cloudflare Turnstile on login/registration when the school enables it;
- section and roster import or editing;
- answer-key editor with shared-key and section-only badges;
- print of standard and custom full-page portrait OMR sheets and OMR ID lists;
- live camera scanning and optional auto-capture;
- review of flagged, multi-mark, or low-confidence items before save (including Scan Confidence labels: Safe to keep / Check before counting / Must review);
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

**Figure 4.4.** Review-before-save / Scan Confidence screen  
*[Insert screenshot]*

**Figure 4.5.** Exam Day Board  
*[Insert screenshot]*

**Figure 4.6.** Mobile item analysis  
*[Insert screenshot]*

### 4.2.2 Web Portal Features

The web portal is a synchronized desk companion. Scanning is not performed in the browser. Implemented features include:

- sign-in with the same teacher account used on the phone;
- **Classes** - sections, search, roster viewing and editing;
- **Prepare** - roster import, answer keys (including exam date, partial credit, multi-answer), print PDFs, OMR ID handouts;
- **Results** - synced scans, item analysis, CSV/PDF export; and
- **Admin** - access control and school overview for authorized administrators.

**Figure 4.7.** Web Classes  
*[Insert screenshot]*

**Figure 4.8.** Web Prepare (keys / print)  
*[Insert screenshot]*

**Figure 4.9.** Web Results / item analysis  
*[Insert screenshot]*

**Figure 4.10.** Admin access control  
*[Insert screenshot]*

The portal does not contain student login, student dashboards, or a web camera scanner.

## 4.3 SYSTEM ARCHITECTURE AND DESIGN

This section presents the structural engineering, data models, and logical workflows designed to replace advertisement-interrupted, connectivity-dependent checking workflows. The architecture is decomposed into three modeling views: Use Case Diagrams for behavioral requirements, Data Flow Diagrams (DFD) for operational information streams, and Entity-Relationship Diagrams (ERD) for relational data structures.

### 4.3.1 Use Case Diagram (Behavioral Model)

The Use Case Diagram defines the system scope and maps interactions between identified actors and the automated modules. Primary actors are the **Teacher** and the **School Administrator**. A student is an examinee whose marks appear on a sheet and whose name appears in the roster; the student is **not** a logged-in system actor.

Teachers prepare rosters and keys, print sheets, scan, review, store, sync, and view analysis. School administrators approve teacher access and may view school-level records appropriate to that role. By establishing clear boundary lines and permission scopes, the design removes multi-stage handoffs that previously depended on third-party free tools or continuous internet during checking.

**Figure 4.11.** Use Case Diagram modeling behavioral actors, system boundaries, and core functional triggers  

*[Insert file: `paper_format_extract/figures/figure_4_11_use_case.png` or `D:\DOWNLOADS\figure_4_11_use_case.png`]*

### 4.3.2 Process Model: Data Flow Diagram (DFD)

The Data Flow Diagram charts the path information takes from external actors, through internal processing, and into persistent storage.

1. **Context Level (Level 0 DFD).** Establishes the entire application as a centralized processing engine interacting with teachers, school administrators, and the printed OMR sheet as an external data carrier.

**Figure 4.12.** Context-Level (Level 0) Data Flow Diagram for the hybrid OMR system

*[Insert file: `paper_format_extract/figures/figure_4_12_dfd_level0.png` or `D:\DOWNLOADS\figure_4_12_dfd_level0.png`]*

2. **Level 1 DFD.** Deconstructs the core sub-processes: roster and key preparation, sheet printing, camera capture and OpenCV reading, review-before-save, local SQLite persistence, JSON synchronization, and teacher web analysis. This modeling explains how exam-day scoring continues from local storage while desk review and item analysis occur after sync.

**Figure 4.13.** Level 1 Data Flow Diagram mapping sub-process logic, data streams, and active data stores  

*[Insert file: `paper_format_extract/figures/figure_4_13_dfd_level1.png` or `D:\DOWNLOADS\figure_4_13_dfd_level1.png`]*

### 4.3.3 Data Model: Relational Schema Design

The Entity-Relationship Diagram maps the normalized logical schema of the centralized relational database and the corresponding local SQLite structures. It illustrates primary keys, foreign keys, and constraints designed to enforce teacher-owned data integrity across users/teachers, sections, students, subjects (answer keys), scan results, and sync metadata.

**Figure 4.14.** Relational database schema design representing entity attributes and key constraints  

*[Insert file: `paper_format_extract/figures/figure_4_14_erd_schema.png` or `D:\DOWNLOADS\figure_4_14_erd_schema.png`]*

| Store | Technology | Contents |
|-------|------------|----------|
| On-device | SQLite | Roster, keys, scores, sync flags; photos in local files |
| Server (production) | PostgreSQL | Teacher accounts, approval status, synchronized academic rows |
| Server (development) | SQLite | Same schema for local API testing |

To support the software architecture, the server schema is normalized to avoid anomalies and information siloing. Explicit ownership constraints regulate access: teachers retain write privileges on their own rows; school administrators retain approval and school-scoped oversight; mobile accounts do not upload scan photographs.

This arrangement reflects the offline-first rule: write locally first, synchronize later, keep photographs off the server.

## 4.4 SYSTEM EVALUATION

The software is evaluated by purposive respondents-Engineering instructors and, when included, school administrators-using two standard instruments planned in Chapter 3: the ISO/IEC 25010 Software Quality Model and the System Usability Scale (SUS).

The evaluation metrics gathered from respondents are processed using the standard arithmetic mean formula:

X-bar = (sum of X) / N

where X-bar represents the mean score, sum of X is the sum of all individual scores, and N represents the total number of evaluators.

Computed N, mean scores, and SUS composites are inserted only after forms are encoded.

### 4.4.1 ISO/IEC 25010 Software Quality Assessment

Respondents rate the system on selected ISO/IEC 25010 characteristics using a 5-point Likert scale (5 = Strongly Agree / Excellent, 4 = Agree / Very Satisfactory, 3 = Neutral / Satisfactory, 2 = Disagree / Fair, 1 = Strongly Disagree / Poor), following Part 2 of the Master Testing Registry / UAT survey.

**Table 4.3.** ISO/IEC 25010 Software Quality Evaluation Results

| Quality characteristic | Mean score | Qualitative interpretation |
|------------------------|-------------------------:|----------------------------|
| Functional suitability | [Insert after encoding] | [Insert] |
| Performance efficiency | [Insert] | [Insert] |
| Usability | [Insert] | [Insert] |
| Reliability | [Insert] | [Insert] |
| Security | [Insert] | [Insert] |
| Maintainability / portability (as administered) | [Insert] | [Insert] |
| Overall software quality mean | [Insert] | [Insert] |

**Interpretation.**  
ISO/IEC 25010 forms were prepared for instructor evaluation in line with the testing plan. Computed means will be inserted here after encoding. No substitute scores are reported. When filled, these means will describe instructor experience with the offline-first OMR workflow, review tools, synchronization, and teacher-facing interfaces-not a laboratory bubble-accuracy percentage.

### 4.4.2 System Functionality Testing Summary

To complement subjective quality evaluation, black-box execution tests were performed across the Master Testing Registry levels and the automated repository suites.

**Table 4.4.** System Functionality Testing Summary

| Testing level | Total tests | Passed | Failed | Pass rate |
|---------------|------------:|-------:|-------:|----------:|
| Unit testing (automated Flutter + web) | 294 | 294 | 0 | 100% |
| Unit testing (Series 100 registry UT-101-UT-107) | 7 | 7 | 0 | 100% |
| Integration testing (IT-101 to IT-104) | 4 | 4 | 0 | 100% |
| System testing (ST-101-ST-106, ST-201-ST-205, ST-301-ST-303, ST-402-ST-403, ST-501-ST-503) | 20 | 20 | 0 | 100% |
| Documented functional execution suite (above) | 325 | 325 | 0 | 100% |

| Evaluator / user role group | Tested functional scope | Notes |
|-----------------------------|-------------------------|-------|
| Researchers / IT verification | Authentication, security, RBAC, APIs, automated suites | Registry Series 100-500 + repository tests |
| School administrators (when included) | Approval desk, access control | ST-105; Admin portal |
| Engineering instructors (end-users) | Prep - print - scan - review - sync - web results | UAT walkthrough path |

**Interpretation.**  
Functional testing covered authentication, local storage, answer-key management, OMR scanning, scan review, synchronization, exports, and web access to synced records. The automated unit suite and the mapped testing-plan cases listed above achieved a full pass on the recorded run/walkthrough date. ST-401 (quantified printed-sheet accuracy) remains outside this 100% claim until a logged agreement rate is inserted in Section 4.4.4. Do not equate this functional pass rate with ISO/SUS excellence scores.

### 4.4.3 System Usability Scale (SUS) Results

Include this subsection only after SUS questionnaires are completed. Data from the 10-item SUS questionnaire are processed using standard SUS scoring rules.

- Respondents: `[Insert count; instructors / administrators only]`
- Calculated System SUS Score: `[Insert] / 100`
- Adjective Rating: `[Insert]`
- Acceptability Grade: `[Insert]`

**Table 4.5.** System Usability Scale (SUS) Score Breakdown by Evaluator Group *(fill after encoding)*

| Evaluator group category | Participant count (N) | Mean SUS score | Adjective rating |
|--------------------------|--------------------------:|---------------:|------------------|
| Engineering instructors | [Insert] | [Insert] | [Insert] |
| School administrators (if any) | [Insert] | [Insert] | [Insert] |
| IT / adviser experts (if any) | [Insert] | [Insert] | [Insert] |
| Overall evaluator mean | [Insert] | [Insert] | [Insert] |

**Interpretation.**  
A System Usability Scale instrument is part of the evaluation plan (Chapter 3 and Testing Registry Part 2). No SUS score is reported in this draft because completed forms have not been computed. When filled, the score will describe ease of use of the teacher mobile and web workflows. It will not measure bubble-recognition accuracy.

### 4.4.4 Optical Mark Recognition Validation

If-and only if-printed sample sheets were compared with manual keys, report that trial here (Testing Registry ST-401).

**Table 4.6.** Sample-sheet comparison with manual scoring *(omit or leave blank if not quantified)*

| Trial condition | Sheets / items | Agreements | Disagreements | Notes |
|-----------------|----------------:|-----------:|--------------:|-------|
| [Printer, paper, light, 100% scale] | [Insert] | [Insert] | [Insert] | [Insert] |

State the printer, scale (must be 100% / actual size), pencil/pen type, and whether review was used. Do **not** insert 99.76% or any other literature figure as if it were this trial.

If printed-sheet validation was performed as a qualitative checklist only:

> Printed-sheet validation was performed as a qualitative checklist (alignment marks visible, sample scans accepted after review). A numeric accuracy rate is not claimed in this chapter until a logged agreement count is entered in Table 4.6.

### 4.4.5 Pre- vs. Post-Automation Operational Metrics

A comparative analysis describes the operational impact of replacing the prior checking workflow (manual tallying and/or advertisement-supported third-party tools) with the developed hybrid OMR system. **Timed percentages appear only if measured.** Table 4.7 therefore uses qualitative variance language consistent with the implemented system.

**Table 4.7.** Pre- vs. Post-Automation Operational Performance Metrics

| Core performance parameter | Pre-automation status (manual / third-party baseline) | Post-automation status (developed system) | System impact |
|----------------------------|------------------------------------------------------|-------------------------------------------|---------------|
| Data integrity during checking | Risk of hand-tally errors; possible key mix across sections | Relational constraints, shared vs section-only keys, review-before-save | Structural integrity improved; doubtful scans require teacher confirmation |
| Checking continuity under poor Wi-Fi | Existing tools may stop or interrupt when connectivity fails | Offline PIN unlock; local SQLite scoring after bootstrap | Exam-day continuity without continuous internet |
| Advertisement interruptions | Free third-party scanners may insert ads | Ad-free mobile workflow | Checking session not interrupted by ads |
| Result recording | Scores often retyped into separate sheets | Local save then JSON sync to school API | Reduced re-entry when teacher syncs later |
| Item analysis | Limited or not institution-owned | Difficulty and discrimination on mobile and web | Teacher-owned analytics after sync |
| Information access | Fragmented device or third-party accounts | Centralized teacher-owned cloud rows + web portal | Desk review on a larger screen after sync |
| Accountability | Weak trail on who changed a grade | Authenticated accounts; review and sync events tied to teacher session | Traceable teacher actions within system scope |

Unsafe unless measured (and therefore **not** claimed here): "88% faster," "75% less friction," or "processing time dropped from 25 minutes to 3 minutes."

## 4.5 DISCUSSION OF RESULTS

The empirical and operational evidence available from the implemented system, independent of unfinished questionnaires, demonstrates that moving from connectivity-dependent or advertisement-interrupted checking to a connected web-mobile OMR workflow improves exam-day continuity, tracking discipline, and teacher-facing analytics.

The architecture matches the problem stated in Chapter 1. Instructors can prepare materials, scan, and score without keeping a browser session alive. The offline model is not "never online." It is **bootstrap once, then exam-day offline, then sync when convenient**. That distinction matters on a new phone or for a newly approved teacher.

The review-before-save step-and the Scan Confidence labels Safe / Check / Must review-is a deliberate limit on full automation. The engine can misread a poorly printed or lightly shaded sheet. Requiring review on flagged and auto-captured sheets reduces the chance that a doubtful reading becomes a final grade without a teacher looking at it.

Shared versus section-only keys address a data-integrity risk that generic OMR apps often leave implicit. When several sections take the same quiz, one shared key is appropriate. When two sections use the same subject name but different answers, a section-only key and the corresponding print/scan labels reduce cross-grading.

The Master Testing Registry cases (UT/IT/ST series) and the automated unit suite (294/294) support the claim that access gates, validation, roster/key workflows, exports, and sync paths behave as designed. They do not, by themselves, prove ISO excellence or a fixed recognition percentage.

The web portal extends the phone; it does not replace it. Larger-screen review of item analysis is useful after sync. It is not a student portal and should not be defended as one.

Honest operational limits remain:

- print scale and toner quality;
- lighting and camera shake;
- incomplete or multiple shading;
- custom-sheet capacity limits (option count versus item count);
- multiple-choice only;
- local academic data stored for offline use; and
- no automatic release of results to a student account.

These limits are consistent with the related studies in Chapter 2, which also reported print and shading sensitivity. They are not treated as defects that the paper hides.

## 4.6 SUMMARY OF FINDINGS

Based on the actual developed system, the Master Testing Registry results, the automated test log, and pending insertion of computed evaluation scores, the study finds that:

1. The system implements an offline-first, teacher-side OMR scanning and grading workflow with local SQLite storage.
2. Daily offline use follows one online registration or sign-in, verification, administrative approval, and PIN setup.
3. Native OpenCV on Android and iOS reads printed sheets; flagged readings can be reviewed before save.
4. Answer keys may be shared across sections or restricted to one section; custom layouts are full-page portrait only.
5. Records synchronize through a Laravel 11 API to PostgreSQL; scan photographs are not uploaded.
6. The Next.js web portal is a teacher and administrator companion for classes, preparation, results, and item analysis. It is not a student login portal.
7. Unit, integration, and system cases drawn from the testing plan, plus the automated repository suite (294/294), passed on the recorded verification run.
8. The system is limited to objective items and remains sensitive to print, lighting, and shading.
9. ISO/IEC 25010, SUS, timed efficiency, and numeric accuracy findings will be stated only from completed instruments: *[Insert final verbal summary after data encoding]*.

