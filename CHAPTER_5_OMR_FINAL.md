# CHAPTER 5
## SUMMARY, CONCLUSIONS, AND RECOMMENDATIONS

This chapter presents the summary of the major findings, conclusions drawn from the results of the system evaluation, and recommendations for the continued use, maintenance, enhancement, and future evaluation of the developed system. The conclusions are based on the results presented and interpreted in Chapter 4, particularly the system requirements verification, functional and non-functional requirements assessment, software quality evaluation using ISO/IEC 25010, system functionality testing, System Usability Scale (SUS) results, and the comparison of pre- and post-automation operational conditions for teacher-side OMR grading.

## 5.1 Summary of Findings

The study focused on the development and evaluation of a hybrid offline-first Optical Mark Recognition (OMR) system designed to address operational challenges associated with connectivity-dependent or advertisement-interrupted checking, fragmented class records, and delayed teacher-facing analytics. The system incorporated a Flutter mobile application for exam-day scanning and grading, a Laravel 11 API for authentication and synchronization, and a Next.js web portal for synchronized academic preparation and result analysis.

The major findings of the study are summarized as follows:

### 1. System Requirements and Functional Requirements

The developed system successfully addressed the identified functional requirements that remain in scope. The Requirements Traceability and Functional Verification Matrix (Table 4.2) showed that FR-01 through FR-11 were verified. FR-12 (student self-service results portal) was removed as out of scope; students do not receive login accounts.

The system provided teacher registration and approval, offline PIN unlock after bootstrap, section and roster management, shared and section-only answer keys, printable standard and custom full-page OMR sheets, camera-based OpenCV reading with review-before-save, local SQLite persistence, later JSON synchronization without photograph upload, Exam Day Board tracking, and teacher/administrator web viewing with item analysis.

These functionalities addressed specific operational problems identified during requirements analysis. Offline local scoring supports checking when campus Wi-Fi is unstable; review-before-save reduces the chance that a doubtful reading becomes a final grade without teacher inspection; and shared versus section-only keys reduce cross-section key mix.

### 2. Non-Functional Requirements

The system also addressed the identified non-functional requirements. Security was implemented through authenticated HTTPS/TLS, Laravel Sanctum tokens, hashed offline PINs, teacher-owned record scoping, and school-administrator approval gates. The system was designed in consideration of the Data Privacy Act of 2012 (RA 10173), including the decision to keep scan photographs on the device.

Performance efficiency was addressed through practical page transitions, sync requests, and on-device scan processing intended for classroom use. Exact seconds-per-sheet or minutes-saved are reported only when timed trials are logged. In terms of portability, the web portal was designed to function across modern browsers (Chrome/Edge), while the mobile application targets Android and iOS devices with camera scanning on a physical phone. Reliability after approved sign-in and PIN setup allows exam-day work to continue from local storage if the network fails (ST-503).

### 3. System Features and Functionalities

The completed system provided two principal interfaces: the Mobile Application and the Teacher/Administrator Web Portal, linked through a shared Laravel API.

The Mobile Application included registration and sign-in, administrative approval, offline PIN unlock, roster and answer-key tools, printable OMR materials, live camera scanning with optional auto-capture, Scan Confidence labels (Safe to keep / Check before counting / Must review), review-before-save, Exam Day Board, local SQLite storage, on-device item analysis, and Sync Now when connectivity is available.

The Web Portal included Classes, Prepare (import, answer keys, print sheets, OMR IDs), Results with item analysis and export, Settings, and Admin access/approval tools. These features provided teachers with a larger-screen desk companion after sync. Scanning is not performed in the browser, and the portal is not a student login system.

### 4. System Architecture and Design

The system architecture incorporated three major modeling approaches: the Use Case Diagram, Data Flow Diagram, and Entity-Relationship Diagram (Figures 4.11 to 4.14).

The Use Case Diagram established the interactions between teachers, school administrators, and the system. A student is an examinee on the roster and sheet, not a logged-in system actor. The Level 0 and Level 1 Data Flow Diagrams illustrated the movement of information from external actors through preparation, print, OpenCV reading, review, local persistence, JSON synchronization, and web analysis, with active stores D1 (on-device SQLite) and D2 (server PostgreSQL). The Entity-Relationship Diagram represented the relational database structure and incorporated primary keys, foreign keys, unique constraints, and teacher ownership through `owner_teacher_id`.

The database was designed as a normalized teacher-owned schema. Academic rows cascade with the owning teacher account. Scan photograph files are excluded from server synchronization by design.

### 5. ISO/IEC 25010 Software Quality Evaluation

ISO/IEC 25010 evaluation forms were prepared for instructor (and, when included, school administrator) assessment in line with the testing plan. Computed characteristic means and the overall software quality mean will be inserted here only after forms are encoded.

*[Insert: overall mean score, verbal interpretation, and per-characteristic means from Table 4.3]*

Until encoding is complete, this chapter does not claim a numeric excellence rating. The non-functional design described in Chapter 4 (security, reliability for offline continuity, usability of teacher task flows, portability of web and mobile clients, and functional suitability for objective-item OMR) remains the verified engineering basis.

### 6. System Functionality Testing

The functionality testing demonstrated a full pass on the recorded verification run for the Master Testing Registry cases mapped to COC OMR and for the combined automated unit suite (294/294: Flutter 242, web Vitest 52).

The detailed testing results covered authentication and access (ST-101 to ST-106), roster and answer-key CRUD (ST-201 to ST-205), search and exports, synchronization including offline-then-sync (ST-503), integration bridges among mobile, SQLite, Laravel API, and web (IT-101 to IT-104), and unit cases for validation and hashing (UT-101 to UT-107). Scan photographs were confirmed as not uploaded.

The results indicate that the system's principal functional components operated according to their intended specifications during testing. ST-401 (quantified printed-sheet accuracy against a fixed agreement threshold) remains outside the automatic 100% claim until a logged agreement rate is inserted in Chapter 4.

### 7. System Usability Scale Results

SUS instruments were prepared for purposive respondents. The overall System Usability Scale score, adjective rating, and acceptability grade will be inserted only after forms are encoded.

*[Insert: overall SUS / 100, adjective rating, acceptability grade, and group means from Table 4.5]*

Until encoding is complete, this chapter does not invent a SUS composite. Chapter 4 documents that screens are arranged around teacher tasks (prepare, scan, review, sync) and that the web portal is a desk companion rather than a scanning station.

## 5.2 Conclusions

Based on the findings presented in Chapter 4, the following conclusions were drawn:

1. The developed system addressed the identified operational and functional requirements that remain in scope.
The verification results for FR-01 through FR-11 demonstrate that the system incorporated the principal functions established during requirements analysis. Teacher authentication and approval, offline PIN unlock, roster and key management, printable sheets, OpenCV scanning with review-before-save, local storage, synchronization without photograph upload, Exam Day Board, and teacher/administrator web analysis corresponded to the identified exam-day and desk-review requirements. A student login portal was intentionally excluded.

2. The developed system demonstrated software quality characteristics consistent with the ISO/IEC 25010 evaluation plan.
Completed instrument scores will be stated after encoding. Independently of questionnaires, the implemented controls for authenticated cloud access, teacher-owned scoping, offline continuity after bootstrap, and review-before-save support the quality attributes emphasized in Chapter 4.

3. The developed system was operationally functional during testing.
The reported functionality testing produced a full pass on the recorded registry walkthroughs and automated suite (294/294), indicating that the tested system functions operated according to their intended behavior during the evaluation. The testing results covered authentication, roster and keys, scan review paths, local persistence, synchronization, exports, and web access to synced records.

4. The developed system is positioned for usable teacher operation pending completed SUS encoding.
SUS composites will be inserted after forms are processed. The implemented interfaces separate exam-day mobile work from later web desk review, which matches the intended division of labor for instructors and school administrators.

5. The developed system improves exam-day continuity relative to connectivity-dependent checking workflows.
After one approved sign-in and PIN setup, scanning and scoring can continue from local SQLite storage when the network fails. This does not claim a fixed minutes-saved figure unless a timed trial is logged. The operational gain is continuity and local save-then-sync rather than an invented speed percentage.

6. The system improves information centralization and teacher-owned traceability for synchronized academic rows.
The developed system replaces fragmented device-only or third-party checking trails with teacher-owned records that can later appear in the school API and web portal. Review and sync events remain tied to the authenticated teacher session. Photographs stay on the device.

7. The developed system provides an integrated platform for mobile exam-day work and web desk review.
By combining the Flutter application with the Next.js portal through Laravel Sanctum and PostgreSQL, the system connects preparation, printing, scanning, review, local scoring, synchronization, and item analysis within a unified teacher-first environment. This integration supports coordination between classroom checking and later administrative or instructor desk use without requiring a student portal.

## 5.3 Recommendations

Based on the findings and conclusions of the study, the following recommendations are proposed:

1. Sustain the implementation of the developed system.
Engineering instructors and school administrators may continue using the developed system for the exam preparation, scanning, review, and synchronization processes covered by the study. Offline PIN unlock, shared and section-only keys, review-before-save, and Sync Now may be incorporated into regular grading activities.

2. Conduct regular system maintenance and monitoring.
Regular preventive maintenance should be performed to ensure continued system availability, performance, security, and reliability. API and portal updates, mobile release builds with `secrets.json` / signed keystore, error monitoring, and backup procedures should be established as part of routine system administration.

3. Strengthen data security and privacy controls.
Security mechanisms should be continuously reviewed. Approval gates, Sanctum token handling, role permissions, teacher-owned scoping, activity awareness around sync, and backup practices should be regularly examined to protect academic and account information and maintain alignment with the Data Privacy Act of 2012 (RA 10173). Scan photographs should remain off the server unless a future, explicitly approved design change is documented and re-tested.

4. Provide continuing user orientation and technical support.
Periodic orientation and technical assistance should be provided, particularly when new teachers are approved or when new features are released. Short guides for print scale (100% / actual size), shading, Scan Confidence labels, shared versus section-only keys, and Sync Now may be maintained for instructors.

5. Continue monitoring system performance.
System administrators and maintainers should periodically monitor scan processing practicality, sync success, page-loading performance, and system availability. Performance monitoring can help identify bottlenecks before they affect examination periods.

6. Maintain regular data backup and recovery procedures.
A systematic backup and recovery policy should protect both on-device academic records (teacher phone backups) and the centralized PostgreSQL store from accidental loss, hardware failure, software errors, or other disruptions. Backup schedules and recovery procedures should be documented and periodically tested.

7. Enhance the system based on actual classroom feedback.
Future enhancements should be based on documented instructor feedback, exam-day observations, and emerging school requirements. Priority may be given to scan confidence clarity, roster/import ergonomics, export formats needed by faculty, and print/layout guidance that reduces review load.

8. Expand future evaluation activities.
Future researchers or system administrators may conduct additional evaluations using larger respondent groups and longer periods of actual classroom deployment. Long-term evaluation may provide additional evidence regarding reliability, maintainability, performance, and user experience under sustained examination conditions.

9. Conduct comparative evaluation after extended implementation.
A follow-up evaluation may compare operational indicators before and after extended system use using actual school records where permitted. Such an evaluation can examine checking continuity under poor Wi-Fi, re-entry reduction after sync, review workload, and-when logged-timed throughput and printed-sheet agreement rates. Invented literature percentages should not be substituted for local measurements.

10. Use the system evaluation results as a basis for continuous improvement.
The findings of this study should not be treated as the endpoint of system development. Instead, the results may serve as a baseline for continuous improvement. Future modifications should be documented, tested against the Master Testing Registry and automated suites, evaluated, and aligned with instructor needs so that the system remains relevant to real exam days.

## 5.4 Proposed Direction for Future Development

Based on the findings of the study, future development may focus on improving scan robustness under varied print and lighting conditions, clearer teacher guidance for custom sheet limits, richer exports for faculty reporting, and carefully scoped school integrations-without weakening offline-first exam-day behavior or introducing a student login portal unless the school formally expands scope.

Future studies may also examine the system using longitudinal classroom data to determine whether the continuity and workflow benefits observed during evaluation are sustained over a longer period of actual implementation. Additional studies may investigate user experience across Engineering instructors and school administrators and assess performance under larger section loads and denser examination calendars.

Overall, the developed system demonstrated that teacher-side OMR checking can be supported through a hybrid offline-first mobile architecture with later web synchronization and analysis. The evaluation results-where completed-and the verified functional registry provide an empirical basis for continued implementation, maintenance, monitoring, and incremental enhancement of the system.
