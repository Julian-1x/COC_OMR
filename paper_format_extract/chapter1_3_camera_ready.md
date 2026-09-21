# CHAPTER 1
## THE PROBLEM

### Introduction

Assessment is an important part of the teaching and learning process because it measures studentsâ€™ understanding and academic performance. In higher education institutions, particularly in engineering programs, instructors commonly use multiple-choice examinations because these allow wide coverage of topics and learning outcomes. Checking these examinations manually, however, requires substantial time and effort and may introduce human errors, especially when classes are large.

To improve efficiency, some instructors use digital examination-checking applications. One application currently used by an instructor in the Department of Engineering at PHINMA Cagayan de Oro College is EvalBee. Although the application supports automated checking, instructors reported that some of its functions depend on a usable internet connection. The institution often experiences slow or inconsistent connectivity, which can interrupt checking and delay the release of results.

In addition, the free version of such applications may contain frequent advertisements and usage limitations. When an instructor must watch advertisements repeatedly to continue using the tool, checking takes longer than expected and productivity is reduced. These interruptions affect both instructors, who must finish grading, and students, who wait for results.

Another limitation of the existing workflow is the limited usefulness of performance feedback for instructional improvement. Commercial checking tools may provide basic scores, but they do not always give instructors an institution-owned, ad-free record of item difficulty, item discrimination, and class performance that can be reviewed later on a larger screen. Without item analysis and a dependable record of results, it becomes more difficult to improve examinations and teaching strategies.

Given these challenges, there is a need for a more reliable examination-checking system that instructors can operate on exam day without depending on continuous internet access or advertisement-supported software. This study developed a mobile-based Optical Mark Recognition (OMR) examination-checking system integrated with a teacher and administrator web portal for later synchronization and analysis. The system is designed to reduce dependence on continuous connectivity, remove advertisement interruptions during scanning, and provide meaningful performance analytics for instructors in the Department of Engineering at PHINMA Cagayan de Oro College. Students benefit from faster checking and from feedback that instructors can export or print; they do not log in to a student portal.

### Statement of the Problem

The Department of Engineering of PHINMA Cagayan de Oro College currently encounters operational challenges in checking multiple-choice examinations. These include dependence on internet connectivity when using existing applications, advertisement-based interruptions in free tools, limited institution-owned analytical reporting, and time-consuming manual verification.

This study aimed to design, develop, and evaluate a Hybrid Offline-First Optical Mark Recognition (OMR) Scanning System with Web-Based Grade Synchronization and Analytics.

Specifically, the study sought to answer the following questions:

1. How can an OMR examination-checking system continue scanning and scoring in areas with limited or no internet connectivity after an instructor has completed initial online account setup?
2. How can interruptions caused by advertisements and unstable internet connections be reduced during scanning and grading?
3. How can the system provide detailed performance analytics and examination reports that help instructors evaluate exam effectiveness?
4. How can the efficiency of examination checking and result processing be improved by automating score computation and organizing records for later release?

### Conceptual Framework (IPO Model)

The conceptual framework of the study illustrates the flow of data and processes in the developed OMR-based assessment system. It is organized into three components: Input, Process, and Output.

**Figure 1.** The IPO framework of the system

The **input** consists of three primary data sources. First, the shaded OMR sheets represent studentsâ€™ responses collected during examinations. These sheets are the raw visual data interpreted by the system. Second, the instructor answer keys provide the correct responses against which student answers are compared. Keys may be shared across several sections or limited to one section. Third, student roster data contain identifying information such as names, school IDs, and OMR IDs so that results can be matched to the correct examinees.

The **process** describes how the inputs are transformed. The mobile application captures OMR sheets with a smartphone camera and processes them through native OpenCV computer-vision routines on Android and iOS. Captured sheets can be scored offline. When a scan is flagged as low-confidence, multi-marked, or otherwise risky, the instructor reviews the reading before the score is saved. All processed records are stored in a local SQLite database on the device. After a one-time online sign-in, email verification, and administrative approval, daily use can continue through an offline PIN. When internet access becomes available, the application performs JSON-based synchronization to a Laravel application programming interface (API), transmitting roster, answer-key, and score recordsâ€”not scan photographsâ€”to a centralized server.

The **output** includes computed scores, item-analysis reports (item difficulty and discrimination), class-level summaries, printable OMR materials, and a teacher/administrator web portal for synchronized records. The portal is a desk companion for preparation and result review. It is not a student login portal and it is not the scanning environment.

### Objectives of the Study

**General Objective**

To design, develop, and evaluate a Hybrid Offline-First Optical Mark Recognition (OMR) Scanning System with Web-Based Grade Synchronization and Analytics for the Department of Engineering of PHINMA Cagayan de Oro College.

**Specific Objectives**

1. Develop an offline-capable OMR scanning application that can operate without continuous internet connectivity after initial online account setup, approval, and PIN creation.
2. Design an ad-free scanning workflow, including review of flagged sheets, so that examination checking can continue without advertisement interruptions.
3. Implement an analytics and reporting module that provides instructors with class performance summaries and item analysis (difficulty and discrimination) on mobile and on the teacher/administrator web portal.
4. Improve the efficiency of examination checking and result processing by automating score computation, storing results locally, and synchronizing records for later review and release by teachers.

### Significance of the Study

**PHINMA Cagayan de Oro College.** The institution gains a customized, ad-free assessment tool that supports academic operations and keeps examination records under institutional control rather than under a third-party free-tier application.

**Department of Engineering.** The department benefits from more organized assessment practice, teacher-owned item analysis, and clearer monitoring of class performance after results are synchronized.

**Instructors.** The system is intended to reduce the workload of manual checking, remove advertisement interruptions during scanning, support exam-day operation without continuous Wi-Fi, and provide review tools before scores are finalized.

**Students.** Students benefit indirectly through faster checking and through clearer feedback that instructors can export, print, or discuss. This study does not provide students with a dedicated login portal.

**Future researchers.** This study may serve as a reference for later work on mobile OMR, offline-first educational systems, and teacher-facing assessment analytics.

### Scope and Limitations of the Study

**Scope of the Study**

This study covers the design and development of a mobile-based OMR examination-checking system integrated with a teacher and administrator web portal. The study locale and initial evaluation focus on instructors in the Department of Engineering at PHINMA Cagayan de Oro College. The implemented software architecture is teacher-account based and may be used by other college instructors, but this study does not claim a completed multi-department rollout.

The **mobile application** is used by instructors to:

- register and sign in online once, then unlock later with an offline PIN;
- manage sections and student rosters;
- create and edit answer keys, including shared keys and section-only keys;
- print standard OMR sheets (30 to 100 items) and scan-safe custom full-page portrait sheets;
- scan multiple-choice answer sheets with a smartphone camera;
- review flagged, low-confidence, or multi-mark readings before saving;
- view an Exam Day Board of missing, review, done, and absent students;
- store results locally and synchronize later when connectivity is available; and
- view item analysis and export records.

The **web portal** is used by teachers and authorized school administrators to manage synchronized classes, prepare rosters and keys, print materials, view results, and review item analysis. Scanning is performed on the phone, not in the browser.

The system supports objective-type (multiple-choice) examinations only. Partial credit may be applied when an instructor defines more than one correct option for a question.

**Limitations of the Study**

1. The system does not check essays, computations, or other subjective answers.
2. Recognition quality depends on print scale (actual size / 100%), printer quality, paper condition, lighting, camera framing, and how completely students shade bubbles.
3. Offline exam-day use requires a prior online registration or sign-in, email verification, administrative approval, and PIN setup. A new phone also requires an online sign-in before offline unlock.
4. Scan photographs remain on the device and are not uploaded. Roster names, answers, and scores are stored locally so grading can continue offline; they are not claimed to be fully encrypted at rest.
5. New custom layouts are limited to full-page portrait configurations that the application accepts as scan-safe. Half-page, quarter-page, and landscape layouts are not offered for new sheets.
6. There is no student web login for viewing personal results. Feedback to students depends on the instructor.
7. Synchronization requires internet access and a correctly configured school API. The system does not guarantee immediate cloud backup while offline.
8. The study does not claim a fixed recognition percentage for all printers, rooms, or shading styles. Any accuracy figure must come from documented validation, not from related literature.

### Definition of Terms

**Batch Scanning.** The process of scanning multiple OMR answer sheets consecutively in one session.

**Computer Vision.** A field of computing that enables software to interpret visual information from images. In this study, OpenCV-based computer vision is used to locate and read marked bubbles.

**Custom Full-Page Layout.** An instructor-defined, portrait, full-page OMR sheet whose bubble geometry remains within the scan contract of the application.

**Entity-Relationship Diagram (ERD).** A visual representation of database structure and relationships among data entities.

**Exam Day Board.** A mobile screen that shows, for a section and subject, which students are still missing, need review, are done, or were marked absent.

**Hybrid Client-Server Architecture.** A design that combines local offline processing on the phone with later server synchronization and web access.

**Image Preprocessing.** Digital steps such as grayscale conversion and thresholding performed before bubble analysis.

**ISO/IEC 25010.** An international standard used to evaluate software quality characteristics such as functional suitability, reliability, performance efficiency, usability, security, and portability.

**Item Analysis.** A statistical review of each question, including difficulty (proportion correct) and discrimination, used by instructors to judge test quality.

**JSON Synchronization.** Transfer of locally stored records to the server in JavaScript Object Notation (JSON) form through authenticated API requests.

**Modified Waterfall Model.** A sequential software development life cycle with feedback loops between stages.

**Offline-First Architecture.** A design in which exam-day scanning and scoring continue from local storage. In this system, offline daily use follows one online account bootstrap and PIN setup; synchronization occurs later when a connection is available.

**Offline PIN.** A hashed unlock code stored on the device so a teacher can open the application without internet after the first approved sign-in.

**Optical Mark Recognition (OMR).** The automated detection of human-marked responses on printed forms.

**Performance Analytics.** Teacher-facing summaries of scores, item difficulty, item discrimination, and class performance on mobile and web.

**Perspective Correction.** An image adjustment that aligns a skewed or rotated sheet before recognition.

**Purposive Sampling.** A non-probability sampling method that selects participants because of their relevance to the study.

**Review-Before-Save.** A grading safeguard that requires the instructor to inspect flagged or low-confidence readings before the score is stored as final.

**Shared Answer Key.** An answer key linked to two or more sections so the same correct answers are used for those sections.

**Section-Only Answer Key.** An answer key limited to one section so it is not used to grade a different section.

**SQLite Database.** A lightweight embedded database used for local storage on the mobile device.

**Synchronization Queue.** A mechanism that keeps unsynced records on the device until upload succeeds.

**System Usability Scale (SUS).** A standardized questionnaire used to measure perceived usability.

**Thresholding.** A computer-vision technique that helps separate marked areas from unmarked areas.

**User Acceptance Testing.** Testing in which intended users try the system and judge whether it meets operational needs.

**Web Portal.** The Next.js teacher and administrator desk companion used to view and prepare synchronized academic data. It is not a student portal.

---

# CHAPTER 2
## REVIEW OF RELATED LITERATURE AND STUDIES

This chapter reviews related literature and studies that provide technical and conceptual support for a mobile-based Optical Mark Recognition (OMR) system. It covers connectivity constraints in Philippine education, local experience with alternative OMR tools, foreign OpenCV-based implementations, and offline-first data handling. The studies cited here describe **prior work**. They are not measurements of the system developed in this capstone.

### Local Literature

In the Philippine context, several studies have identified technological and infrastructural challenges that affect digital learning tools. Borbon, Jr. et al. (2024) discussed a â€œThird-Level Digital Divideâ€ in regions such as Northern and Southern Mindanao, where slow and costly internet access limits the effectiveness of digital educational tools. This supports the need for classroom systems that do not require a continuous connection during the most time-critical taskâ€”in this study, exam-day scanning and scoring.

Local research conducted by Silao and Luciano (2021) evaluated automated OMR systems using ISO/IEC 25010 software quality standards and concluded that automated item analysis can reduce teacher workload while supporting more systematic assessment review. Applications such as EvalBee are commonly used in Philippine schools. Studies and user reports indicate that free versions of such applications may contain advertisements and may require internet access for some functions, which can interrupt checking and reduce efficiency.

These local findings suggest that automated checking tools are useful, but their practicality in low-connectivity settings is limited when the tool depends on continuous internet access or advertisement-supported use.

### Local Studies

Recent Philippine research provides empirical support for mobile OMR adoption. A 2024 study by Cuerdo and Sinfuego at the University of Cabuyao evaluated EvalBee, an Alternative Optical Mark Recognition (AOMR) application, using a mixed-methods approach with 200 test papers and five faculty participants. Their quantitative findings showed large efficiency gains for that application: AOMR processed test papers in 0.05 minutes compared with 6.57 minutes manuallyâ€”a 130-fold increase in speedâ€”while maintaining equivalent accuracy and reliability (Cohenâ€™s *d* = 1.00, large effect size).

Those figures belong to Cuerdo and Sinfuego (2024). They are **not** the measured speed or accuracy of the system developed in this study.

Qualitative interviews in that study reported reduced workload, automated score recording, and easier result distribution. Participants also noted technical challenges: dependence on precise camera positioning, sensitivity to answer-sheet printing quality, and the need for proper student shading. Those constraints are relevant to any camera-based OMR design, including the present system, and they explain why review-before-save and print-quality guidance are part of the implemented workflow.

### Foreign Literature

Optical Mark Recognition has been widely studied as a method of checking multiple-choice examinations. According to KÃ¼Ã§Ã¼kkara and TÃ¼mer (2018), image-processing libraries such as OpenCV and thresholding algorithms can achieve recognition accuracy of up to 99.76% **in their reported experimental setting**. That result shows that mobile or software-based OMR can, under controlled conditions, approach the reliability of dedicated hardware. It must not be read as the accuracy of the present system.

Foreign systems such as CheckIt have shown that smartphone-based checking can reduce instructor workload and return results more quickly than purely manual scoring. International discussion of learning analytics also suggests that data-driven feedback can help instructors examine test quality. Some foreign literature discusses artificial-intelligence methods in OMR. The system in this study uses OpenCV-based computer vision (preprocessing, alignment, and bubble analysis). It is not presented as a separate machine-learning or generative-AI product.

Another relevant foreign concept is offline-first software architecture, which emphasizes local databases such as SQLite so that an application can continue when the network is unavailable. This approach supports continuous classroom use and reduces the risk of losing work when connectivity is unstable.

### Foreign Studies

International implementations demonstrate the technical viability of OpenCV-based OMR. A 2022 Indian study by Pushpa, Mallesh, and Das developed an e-assessment system using OpenCV and Pythonâ€™s Django framework for automated multiple-choice evaluation. Their system included student management, image-based exam assessment, result analysis, and graphical visualization. The researchers reported that large numbers of images could be processed quickly enough for practical use. This supports the feasibility of computer-vision assessment; it does not mean that the present Flutter and Laravel implementation is the same system.

The same authors noted a limitation: their software could be used only offline at the time of publication. That split between offline processing and later web access is relevant in the Philippine setting, where connectivity is intermittent. The present study addresses that split through local SQLite storage and later JSON synchronization to a school-hosted APIâ€”not by copying the Django implementation.

Another relevant implementation is CheckIt (Patel et al., 2015), which demonstrated that smartphone scanning could process a page in under two seconds in that studyâ€™s tests while maintaining high accuracy. CheckIt established the feasibility of low-cost mobile OMR, though it focused more on scanning speed and accuracy than on offline-first institutional sync, teacher-owned item analysis, or shared versus section-only keys.

### Synthesis of Related Literature and Studies

The reviewed foreign and local studies indicate that mobile OMR is technically feasible and can be highly accurate under documented conditions. Foreign research emphasizes image-processing precision and analytics, while local studies emphasize infrastructure limits, teacher workload, and accessibility. Both perspectives agree that automation can reduce repetitive manual checking when printing, lighting, and shading are adequate.

The synthesis also shows gaps. Cuerdo and Sinfuego (2024) demonstrated EvalBeeâ€™s efficiency but also its dependence on precise capture conditions and, in free use, possible interruptions. Pushpa et al. (2022) showed a robust OpenCV pipeline but remained offline-only. CheckIt (Patel et al., 2015) showed mobile feasibility but did not provide an institution-owned hybrid of exam-day offline grading and later teacher web analysis. These studies justify a **teacher-owned**, ad-free, offline-first scanner with later synchronization. They do not justify claiming a student results portal, nor do they transfer their accuracy percentages to this product.

### Research Gap

Despite the number of mobile OMR applications globally, a gap remains in combining the following in one institution-owned workflow for Philippine higher education:

1. **Infrastructureâ€“technology mismatch.** Free tools such as EvalBee, as discussed by Cuerdo and Sinfuego (2024), may require internet access or expose users to advertisements. Offline-only systems such as Pushpa et al. (2022) limit later data access. Instructors at PHINMA Cagayan de Oro College need exam-day scanning that continues without Wi-Fi, plus later sync when a connection returns.

2. **Teacher-owned analytics, not a student portal.** Existing studies often emphasize scanning accuracy (KÃ¼Ã§Ã¼kkara & TÃ¼mer, 2018; Patel et al., 2015) but do not provide a localized, ad-free portal where **instructors and authorized administrators** can review synchronized results and item analysis after exam day. The gap addressed by this study is teacher-facing analysis and record continuityâ€”not student self-service login.

3. **Context-specific operational safeguards.** Local literature on the digital divide (Borbon et al., 2024) and teacher workload (Silao & Luciano, 2021) supports an Engineering-focused implementation, but published tools do not fully describe the classroom safeguards needed to avoid wrong-section grading: review of risky scans, shared versus section-only answer keys, and scan-safe custom sheets.

This study addresses those gaps by developing an OpenCV-based mobile scanner with local storage, offline PIN unlock after approved sign-in, later Laravel synchronization, and a Next.js teacher/administrator portal for preparation and analysis.

---

# CHAPTER 3
## METHODOLOGY

This chapter presents the research design, respondents, locale, instruments, and the software development process used to build and evaluate the Hybrid Offline-First Optical Mark Recognition (OMR) Scanning System with Web-Based Grade Synchronization and Analytics. The methods were selected so that the technical product and its evaluation remain aligned with the operational needs of instructors in the Department of Engineering at PHINMA Cagayan de Oro College.

### Research Design

This study used a developmental research design with a descriptive-evaluative approach. The primary focus was the design, development, and evaluation of a mobile OMR checking system with offline exam-day capability and a teacher/administrator web portal for later synchronization and analysis.

The developmental approach was used to build a solution to the documented problems of inconsistent connectivity, advertisement-supported tools, and limited institution-owned analytics. The descriptive-evaluative method was applied to assess whether the implemented modules operate as designed and how usable instructors find the mobile scanner and teacher web portal. This design is appropriate for an information-technology capstone in which the creation of a technical tool and its validation against quality standards are the main objectives.

Scanning accuracy, when reported, must be based on comparison of system readings with manual scoring of printed sample sheets. Related-literature percentages are not used as product accuracy.

### Respondents and Sampling Technique

The respondents of the study are the intended **system users** within PHINMA Cagayan de Oro College:

- **Instructors** from the Department of Engineering who handle multiple-choice assessments and will use the mobile application and the teacher web portal. Approximately 5â€“7 instructors are the planned evaluation group.
- **School administrators**, if they participate in access approval or school-level oversight on the web portal.

The study uses purposive sampling. Participants are selected because they are directly involved in examination checking and face the connectivity and workload problems described in Chapter 1.

Students are **not** treated as web-portal users because the implemented system has no student login. If students are later asked for feedback, that feedback should concern the speed or clarity of results released by teachers, not a student dashboard that does not exist.

### Research Locale

The study was conducted at PHINMA Cagayan de Oro College, with evaluation focused on the Department of Engineering. This locale was selected because instructors there need an assessment tool that can continue during inconsistent campus connectivity. Faculty rooms and ordinary classroom lighting are the intended setting for scanner trials, rather than a laboratory scanner room only.

### Data Gathering Procedure

The researchers followed this sequence:

1. **Permission and coordination.** Formal permission was requested from the Department of Engineering to study current examination workflows.
2. **Requirements gathering.** Interviews and observations were conducted with engineering instructors to identify checking difficulties, desired reports, and OMR layout needs.
3. **System development.** Development followed the Modified Waterfall Model. Each phase produced design or software deliverables that were reviewed before the next phase.
4. **System testing.** Modules were tested for scanning behavior, local storage, review-before-save, synchronization, and web access. Automated tests in the project repository support layout, scoring, and data-integrity checks; they do not replace classroom validation.
5. **System evaluation.** Instructors (and administrators, if included) evaluate the system using ISO/IEC 25010 and the System Usability Scale (SUS).
6. **Compilation and analysis.** Evaluation results are tabulated in Chapter 4 only after they are actually computed. No substitute numbers are used.

### Research Instruments

The study uses two standard instruments:

1. **ISO/IEC 25010 questionnaire** â€” to evaluate functional suitability, reliability (including offline use), performance efficiency, usability, security, and portability as perceived by instructor-users.
2. **System Usability Scale (SUS)** â€” to measure how easy instructors find the mobile scanner, review flow, and teacher web portal.

Both instruments use a five-point Likert scale. Final means and SUS scores appear only in Chapter 4 when computed from completed forms.

### System Development Life Cycle (SDLC)

The researchers adopted the Modified Waterfall Model. The model is sequential but allows feedback loops when a later test or user comment requires a return to design or implementation.

**Figure 3.1.** Modified Waterfall Model of the SDLC

The phases were Planning, Requirements Gathering, Analysis and Design, Development, Testing and Evaluation, and Deployment.

### Planning Phase

In the Planning Phase, the researchers defined the purpose, users, and expected outputs of the system based on the problems in Chapter 1. Consultations with Engineering instructors were used to understand the current checking workflow.

The planned strategy was:

- offline-first scanning after one online account bootstrap;
- an ad-free mobile workflow;
- local SQLite storage and later API synchronization; and
- a teacher/administrator web portal for preparation and analysis.

Project boundaries were set as follows: multiple-choice examinations only; standard and scan-safe custom full-page portrait sheets; teacher and school-administrator roles; no student portal; and a two-semester capstone timeline.

### Requirements Gathering Phase

This phase identified functional and non-functional requirements from instructor interviews and observation of the current checking process, including the use of existing OMR applications.

**Identified issues**

- Dependence on usable internet during checking when using some existing tools
- Advertisement interruptions in free OMR applications
- Limited institution-owned item analysis and class reports
- Delays in releasing results to students because checking is slow or interrupted
- Risk of mixing answer keys across sections if key ownership is unclear
- Need to continue grading when campus Wi-Fi is unavailable

The earlier paper listed â€œabsence of a student result portalâ€ as a gathered requirement. The implemented system does **not** include student login. Result release remains an instructor responsibility through exports, printouts, or class discussion. That change is treated as a scope decision, not as an unimplemented defect hidden from the reader.

#### Functional Requirements

The system shall:

1. Allow a teacher to register, verify email, and sign in; a school administrator shall approve the account before full use.
2. Allow the teacher to set an offline PIN and unlock the application without internet after the first approved sign-in.
3. Capture and read shaded OMR sheets using a smartphone camera and native OpenCV processing.
4. Support review of flagged, low-confidence, or multi-mark readings before a score is saved.
5. Allow offline scoring and local storage in SQLite.
6. Synchronize roster, answer-key, and result records to the school API when connectivity is available (scan photos remain local).
7. Manage sections, student rosters, and OMR IDs.
8. Allow creation of shared and section-only answer keys, including optional partial credit for multi-answer items.
9. Generate printable standard sheets (30â€“100 items) and scan-safe custom full-page portrait sheets.
10. Provide instructors with item analysis (difficulty and discrimination) and class summaries on mobile and web.
11. Provide teachers and authorized administrators with a web portal for synchronized classes, preparation, results, and access control.
12. Support batch or continuous scanning within one session, with review required when auto-capture is used.

The system shall **not** provide a student web account for viewing personal results.

#### Non-Functional Requirements

- Local records shall remain available during offline operation so that a completed scan is not lost when the network drops.
- Interfaces shall be usable by non-technical instructors during exam-day conditions.
- Synchronization shall use authenticated HTTPS/TLS.
- Scanning shall be usable under ordinary classroom lighting, with the understanding that poor light, shrink-to-fit printing, or light shading can reduce recognition quality.
- Individual sheets shall be processed within a time that is practical for classroom throughput; exact seconds-per-sheet are reported only if measured.
- The application shall be ad-free.

#### Optical Mark Recognition (OMR) Processing Requirements

- Image preprocessing through grayscale conversion and thresholding
- Perspective or alignment correction for sheets that are slightly skewed
- Location of timing marks, row marks, and predefined bubble regions
- Shading analysis of each option
- Score computation against the selected answer key
- Flagging of blank, multi-mark, or low-confidence items for instructor review

#### Offline Synchronization Requirements

The system uses an offline-first design. After account bootstrap, scanning and scoring continue from the device database. Unsynced records are queued and uploaded when the teacher syncs and a connection is available. Eventual consistency is the goal; the system does not claim instantaneous cloud copies while offline.

### Analysis and Design Phase

Requirements were translated into process models, data structures, and interfaces.

#### System Analysis

User interaction was modeled with use-case and process-flow diagrams.

**Primary actors**

- **Teacher (Instructor)** â€” prepares rosters and keys, prints sheets, scans, reviews, stores, syncs, and views analysis.
- **School Administrator** â€” approves teacher access and may view school-level records appropriate to that role.

A **Student** is an examinee whose marks appear on a sheet and whose name appears in the roster. The student is not a logged-in system actor.

Typical flow: the teacher prints sheets, administers the exam, scans each paper, reviews flagged items, saves the score locally, and later synchronizes. The teacher may then open the web portal to review class results and item analysis.

#### System Architecture Design

The system uses a hybrid client-server architecture with three layers.

| Component | Description |
|-----------|-------------|
| Mobile application (Flutter) | Exam-day tool: PIN unlock, roster, keys, print, OpenCV scan, review, Exam Day Board, local SQLite, sync |
| Backend API (Laravel 11 + Sanctum) | Authentication, teacher approval, token-protected sync, teacher-owned records |
| Web portal (Next.js / React) | Teacher/administrator desk companion: classes, prepare, results, item analysis, access control |

The mobile application operates independently during scanning. When connectivity is available, records are transmitted to the API. The web portal reads the same synchronized data. There is no camera scanner on the web.

#### Database Design

| Database | Technology | Purpose |
|----------|------------|---------|
| Local database | SQLite | Sections, students, subjects/answer keys, scan results, sync flags, and related exam-day records on the phone |
| Central database | PostgreSQL in production; SQLite supported in development | Consolidated teacher-owned records, credentials, approval status, and synchronized academic data |

Scan photographs are stored on the device only and are not part of the central schema.

The logical structure is modeled in an Entity-Relationship Diagram covering teachers/users, sections, students, subjects (answer keys), scan results, and sync metadata.

#### Optical Mark Recognition (OMR) Processing Design

1. Image capture with the smartphone camera
2. Grayscale conversion and thresholding
3. Alignment using the printed scan contract (corner markers, timing marks, row marks)
4. Identification of bubble regions for the active layout
5. Shading detection
6. Comparison with the selected answer key
7. Instructor review when the engine flags uncertainty
8. Local save, then later sync of the numeric/text result

The pipeline is designed for ordinary classroom use. It does not guarantee uniform accuracy under poor print, dim light, or incomplete shading.

#### Synchronization Design

- Offline: results are stored locally and marked unsynchronized.
- When the teacher syncs and a connection exists: unsynchronized records are sent through authenticated HTTPS to the Laravel API.
- After success: local sync status is updated.
- Photos are not uploaded.

#### User Interface Design

| Platform | Main screens / modules |
|----------|------------------------|
| Mobile application | Sign-in and verification, PIN unlock, dashboard, sections and roster, answer-key editor (shared / section-only badges), print, scanner, review, Exam Day Board, item analysis, settings/sync |
| Web portal | Sign-in, Classes, Prepare (roster, keys, print, OMR IDs), Results and item analysis, Settings, Admin access control |

Information is shown in structured lists, tables, and summaries. The web portal does not include a student dashboard.

#### Security and Access Control

The system implements:

- email-and-password authentication;
- email verification;
- administrative approval of new teachers;
- hashed offline PIN on the device (hash may also be backed up to the account);
- teacher-owned rows on the server (`owner_teacher_id`);
- school-administrator read/approval functions; and
- HTTPS/TLS for API communication.

Cloudflare Turnstile may be required on login or registration when configured.

Roster names, answers, and scores are stored locally because offline grading requires them. The study does **not** claim that all local academic data are encrypted at rest. Scan photos remain on the device.

### Development Phase

#### Mobile Application Development

The mobile application was developed in Flutter with a Dart SDK 3.x-compatible toolchain. OMR reading uses native OpenCV bridges on Android and iOS, not React Native.

Implemented capabilities include:

- account sign-in, verification, and PIN unlock;
- roster and section management;
- shared and section-only answer keys;
- standard and custom full-page print;
- live and auto-capture scanning;
- review-before-save;
- Exam Day Board;
- local SQLite storage;
- manual sync when online; and
- item analysis and exports.

#### Backend Development

The backend was implemented in Laravel 11 on PHP 8.2+ with Laravel Sanctum tokens. It handles registration, login, password reset, teacher approval, and sync endpoints for sections, students, subjects, scan results, and related records.

#### Web Portal Development

The web portal was implemented with Next.js, React, and TypeScript. It allows teachers to work with synchronized classes, prepare materials, and view results and item analysis. Authorized administrators use Access Control. Students do not sign in.

### Testing and Evaluation Phase

#### Functional Testing

Core modules are tested for:

- authentication and approval gates;
- PIN unlock after bootstrap;
- OMR scanning against the printed layout contract;
- review-before-save behavior;
- local storage;
- shared versus section-only key guards; and
- synchronization and web display of synced records.

#### Integration Testing

The following connections are validated:

- mobile application and local SQLite;
- mobile application and Laravel API;
- web portal and Laravel API.

#### Optical Mark Recognition (OMR) Accuracy Testing

A controlled comparison using printed, shaded sample sheets is the proper accuracy method. System readings are compared with manual scoring under ordinary classroom lighting. Results appear in Chapter 4 only if this comparison was actually recorded (see also the projectâ€™s scan-validation checklist). Literature values such as 99.76% are not used as the product score.

#### User Acceptance Testing

Selected instructors test the mobile and web workflows and complete ISO/IEC 25010 and SUS instruments. The evaluation focuses on functionality, reliability of offline use, usability, and perceived efficiency. Students are not asked to evaluate a student portal.

### Deployment Phase

1. The Laravel API and PostgreSQL database are configured in the production environment.
2. The mobile application is installed on instructor devices as a release build that includes the school API address.
3. The web portal is deployed for teacher and administrator access.
4. Orientation is given to participating instructors.

Formal evaluation then uses the completed ISO/IEC 25010 and SUS forms.

### Technology Stack

| Layer | Technology | Notes |
|-------|------------|--------|
| Mobile application | Flutter; Dart SDK `>=3.0.0 <4.0.0` | Cross-platform teacher app |
| OMR engine | Native OpenCV on Android and iOS | Bridged into Flutter; not `react-native-opencv` |
| Local database | SQLite | Offline exam-day records |
| Web portal | Next.js, React, TypeScript | Teacher/administrator desk companion |
| Backend | Laravel 11, PHP 8.2+, Laravel Sanctum | Auth, approval, sync API |
| Central database | PostgreSQL (production); SQLite (development) | Server records |
| Development tools | Visual Studio Code / Cursor, Git, Flutter SDK | â€” |
| Local API hosting (dev) | Laravel Herd, XAMPP, or `php artisan serve` | Production uses a school or cloud host |
| Testing devices | Android (API 29+) and iOS (15+) physical devices | Camera scanning requires a real device |

**Technical environment**

- Windows 10 or 11, or macOS, for development
- Node.js 18+ LTS for the web portal
- PHP 8.2+ for the API
- Android and iOS physical devices for camera tests

### Ethical Considerations

1. **Informed consent.** Participants who evaluate the system should receive an informed-consent form describing purpose, procedures, risks, and the right to withdraw.
2. **Data privacy and confidentiality.** Synchronization uses authenticated HTTPS/TLS. The offline PIN is stored as a hash. Scan photographs remain on the device and are not uploaded. Roster names, answers, and scores are stored locally to support offline grading and are synchronized to the school server when the teacher syncs. Access is limited to the teacherâ€™s own records and to authorized administrators. Evaluation reports should present grouped or anonymized findings rather than publishing identifiable student scores.
3. **Institutional approval.** Formal permission from the college or department should be on file before classroom data collection.
4. **Honest limitation.** The system does not claim that no sensitive student information exists on the phone, and it does not claim field-level encryption of every grade during sync. Transport security and account scoping are the implemented controls.

---

## REFERENCES

Borbon, Jr., et al. (2024). Bridging the third-level digital divide: An examination of digital inequalities among different groups in higher education. *Journal of Innovative Research in Social and Educational Administration, 22*(3), 45â€“62. http://www.seaairweb.info/journal/articles/JIRSEA_v22_n03/JIRSEA_v22_n03_Article07.pdf

Cuerdo, R. P., & Sinfuego, et al. (2024). Enhancing face-to-face evaluation using alternative optical mark recognition: A case study from the University of Cabuyao's college of education. *HCMCOUJS-Social Sciences, 14*(1), 118â€“132. https://doi.org/10.46223/HCMCOUJS.soci.en.14.1.2905.2024

KÃ¼Ã§Ã¼kkara, S., & TÃ¼mer, et al. (2018). An image processing oriented optical mark recognition and evaluation system. *Journal of Engineering Technology, 6*(3), 112â€“125. https://www.researchgate.net/publication/330977246

Patel, R., Sanghavi, S., et al. (2015). CheckIt â€“ A low-cost mobile OMR system. *International Journal of Computer Applications, 120*(15), 12â€“16. https://www.researchgate.net/publication/280776405

Pushpa, G., Mallesh, A., & Das, et al. (2022). Enhancing e-assessment with image processing for exam evaluation. *Industrial Engineering Journal, 51*(10), 100â€“106. https://apgcu.edu.in/pdf/mca-publications/2022-13.pdf

Silao, R. P., Luciano, et al. (2021). Effectiveness of automation in evaluating test results using EvalBee as an alternative Optical Mark Recognition (OMR): A quantitative-evaluative approach from a Philippine public school. *International Journal of Theory and Application in Elementary and Secondary School Education, 3*(2), 61â€“75. https://doi.org/10.31098/ijtaese.v3i2.661

---
