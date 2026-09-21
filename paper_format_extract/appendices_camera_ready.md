# APPENDICES

**APPENDIX A:** Letter Requesting Permission to Conduct the Study and System Development  
**APPENDIX B:** Gantt Chart of System Development Activities  
**APPENDIX C:** System Requirements and Requirements Traceability Matrix  
**APPENDIX D:** System Functionality Testing Documentation  
**APPENDIX E:** ISO/IEC 25010 Software Quality Evaluation Questionnaire  
**APPENDIX F:** ISO/IEC 25010 Evaluation Summary  
**APPENDIX G:** System Usability Scale (SUS) Questionnaire  
**APPENDIX H:** System Usability Scale Results  
**APPENDIX I:** Evaluator Group and Functional Testing Matrix  
**APPENDIX J:** System Architecture and Design Documentation  
**APPENDIX K:** System Interface Documentation  
**APPENDIX L:** System Evaluation Consent and Respondent Information Sheet  
**APPENDIX M:** Documentation of System Testing and Evaluation  
**APPENDIX N:** Summary of System Evaluation Results  

---

## APPENDIX A: Letter Requesting Permission to Conduct the Study and System Development

*[Insert signed letter requesting permission to conduct the study and develop/evaluate the Hybrid Offline-First OMR Scanning System at Cagayan de Oro College / PHINMA Education, addressed to the appropriate college or campus authority.]*

---

## APPENDIX B: Gantt Chart of System Development Activities

*[Insert Gantt chart of system development activities covering requirements, design, implementation (mobile / API / web), testing, evaluation, and documentation.]*

**Figure B.1.** Gantt Chart of System Development Activities  
*[Insert]*

---

## APPENDIX C: System Requirements and Requirements Traceability Matrix

### C.1 Functional Requirements

The following matrix presents the functional requirements implemented and verified in the developed Hybrid Offline-First Optical Mark Recognition (OMR) Scanning System with Web-Based Grade Synchronization and Analytics. FR-12 (student self-service portal) was removed as out of scope.

| Requirement ID | Functional Requirement | Description | Verification Method | Status |
|----------------|------------------------|-------------|---------------------|--------|
| FR-01 | Teacher authentication | Authorized teachers can register, verify email, and sign in on mobile and web. New teachers remain pending until school-administrator approval. | ST-101-ST-106; IT-101-IT-102 | Verified |
| FR-02 | Offline PIN unlock | After bootstrap, teachers can unlock the app with a hashed offline PIN without internet. | End-to-end PIN unlock; ST-503 | Verified |
| FR-03 | Section and roster management | Teachers can create or sync sections and maintain student names, school IDs, and OMR IDs. | ST-201-ST-204; IT-104 | Verified |
| FR-04 | Answer-key management | Keys may be shared across sections or restricted to one section; partial credit is available for multi-answer items. | ST-202; answer-key scope tests | Verified |
| FR-05 | Printable OMR materials | Standard 30-100 sheets, scan-safe custom full-page portrait sheets, and OMR ID lists can be printed. | ST-402; print walkthroughs | Verified |
| FR-06 | Camera-based OMR (OpenCV) | The phone captures the sheet; native OpenCV on Android/iOS reads marks against the printed layout contract. | Scan walkthroughs; review path | Verified |
| FR-07 | Review-before-save | Flagged, low-confidence, or multi-mark items can be inspected before the score is saved; auto-capture requires review. | Review walkthroughs; Scan Confidence tests | Verified |
| FR-08 | Local offline storage | Roster, keys, and scores persist in SQLite; scan photos stay on the device. | SQLite integration; ST-503 | Verified |
| FR-09 | Academic record sync | Teachers upload/download academic records through the Laravel API over HTTPS; photos are not synced. | IT-102/IT-104; ST-502-ST-503 | Verified |
| FR-10 | Web desk companion | Synced classes, results, and item analysis (difficulty and discrimination) are available on the web portal. | Web-API integration; ST-301-ST-303 | Verified |
| FR-11 | Exam Day Board | Teachers can see missing, review, done, and absent students for a section and subject. | Mobile walkthrough | Verified |
| FR-12 | Student self-service results portal | Students do not receive login accounts. Feedback is released by the teacher. | Scope decision | Removed / out of scope |

### C.2 Non-Functional Requirements

| Quality Area | Requirement | Implementation / Verification |
|--------------|-------------|-------------------------------|
| Security | Restrict access according to roles and ownership. | Sanctum tokens; hashed offline PIN; teacher-owned rows; admin approval gates; ST-105 |
| Data Privacy | Protect personal and academic information. | HTTPS/TLS; RA 10173-aligned handling; scan photographs kept on device |
| Performance Efficiency | Maintain practical response during classroom use. | Page transitions, sync, and scan processing checked in walkthroughs; timed metrics only if logged |
| Portability | Support intended platforms. | Modern web browsers (Chrome/Edge); Flutter Android/iOS with camera on a physical device |
| Reliability | Maintain consistent operation after bootstrap. | Offline-then-sync (ST-503); local SQLite persistence |
| Maintainability | Support continued maintenance and modification. | Structured Flutter / Laravel / Next.js codebase and normalized schema |
| Usability | Support teacher task flows. | Prepare-scan-review-sync layout; SUS reported only after encoding |

---

## APPENDIX D: System Functionality Testing Documentation

### D.1 Unit Testing

Unit testing was conducted to verify individual system functions before integration. Registry Series 100 cases (UT-101 to UT-107) and the combined automated repository suite were executed.

| Testing Level | Tests Executed | Passed | Failed | Pass Rate |
|---------------|---------------:|-------:|-------:|----------:|
| Registry unit cases (UT-101 to UT-107) | 7 | 7 | 0 | 100% |
| Automated Flutter unit / widget (`flutter test`) | 242 | 242 | 0 | 100% |
| Automated web unit (Vitest, `omr_web`) | 52 | 52 | 0 | 100% |
| Combined automated unit suite | 294 | 294 | 0 | 100% |

### D.2 Integration Testing

Integration testing was conducted to verify interaction among the mobile client, local SQLite store, Laravel API, and web portal.

| Testing Level | Tests Executed | Passed | Failed | Pass Rate |
|---------------|---------------:|-------:|-------:|----------:|
| Integration Testing (IT-101 to IT-104) | 4 | 4 | 0 | 100% |

Additional walkthrough paths verified: mobile-SQLite offline save; mobile-API sync of academic rows; web-API Classes/Prepare/Results/Admin. Scan-photo upload to the server is not applicable by design.

### D.3 System Testing

System testing was conducted to verify complete teacher workflows.

| Testing Level | Tests Executed | Passed | Failed | Pass Rate |
|---------------|---------------:|-------:|-------:|----------:|
| System Testing (ST series mapped in Chapter 4) | [Insert final ST count] | [Insert] | 0 | [Insert]% |

Note: ST-401 (quantified printed-sheet accuracy) is reported separately when a logged agreement rate is available; it is not treated as automatically passed by registry membership alone.

### D.4 Functional Test Case Template (COC OMR)

| Test Case ID | Function Tested | Test Procedure | Expected Result | Actual Result | Status |
|--------------|-----------------|----------------|-----------------|---------------|--------|
| TC-01 | Teacher authentication | Enter valid approved credentials | Authorized teacher is granted access | As expected | Passed |
| TC-02 | Role-based access | Non-admin opens Admin desk | Access denied / redirected | As expected | Passed |
| TC-03 | Roster import | Import valid CSV/Excel class list | Sections and students created | As expected | Passed |
| TC-04 | Shared / section-only key | Create key with scope badge | Scope label matches print/scan intent | As expected | Passed |
| TC-05 | Print OMR sheet | Print standard or custom full-page sheet at 100% scale | Sheet prints with alignment marks | As expected | Passed |
| TC-06 | Camera OMR scan | Capture a printed sheet | Readings and confidence flags produced | As expected | Passed |
| TC-07 | Review-before-save | Open flagged / Must-review scan | Teacher can accept, edit, or reject before save | As expected | Passed |
| TC-08 | Offline save | Save scores with network off | Records persist in SQLite | As expected | Passed |
| TC-09 | Sync Now | Sync academic rows when online | Cloud updated; photos not uploaded | As expected | Passed |
| TC-10 | Exam Day Board | Open board for section/subject | Missing / review / done / absent shown | As expected | Passed |
| TC-11 | Web results / item analysis | Open synced results on portal | Scores and item analysis displayed | As expected | Passed |
| TC-12 | Export | Export CSV/PDF of results | File generated | As expected | Passed |
| TC-13 | Data validation | Submit invalid email / short password / blank required fields | Submission blocked with clear errors | As expected | Passed |
| TC-14 | Offline PIN unlock | Unlock app offline after PIN setup | App unlocks without internet | As expected | Passed |
| TC-15 | Admin approval | Approve pending teacher | Teacher can proceed to productive use | As expected | Passed |
| TC-16 | End-to-end exam path | Prepare - print - scan - review - save - sync - web view | Workflow completes successfully | As expected | Passed |

---

## APPENDIX E: ISO/IEC 25010 Software Quality Evaluation Questionnaire

**Instructions**

Please evaluate the developed Hybrid Offline-First OMR Scanning System based on your actual experience using the system. Place a check mark beside the response that best represents your assessment.

**Rating Scale**

| Rating | Interpretation |
|-------:|----------------|
| 5 | Strongly Agree / Excellent |
| 4 | Agree / Very Satisfactory |
| 3 | Neutral / Satisfactory |
| 2 | Disagree / Fair |
| 1 | Strongly Disagree / Poor |

### E.1 Functional Suitability

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
|----:|-----------|---|---|---|---|---|
| 1 | The system provides the functions required for exam preparation, OMR scanning, review, and grade recording. | | | | | |
| 2 | The system performs its intended scanning and scoring functions accurately enough for classroom use when sheets are printed and shaded correctly. | | | | | |
| 3 | The system provides appropriate functions for teacher operations (roster, keys, print, scan, review, sync). | | | | | |
| 4 | The system supports instructors in completing exam-day checking without continuous internet after setup. | | | | | |
| 5 | The system provides useful results information and item analysis for teachers. | | | | | |

### E.2 Performance Efficiency

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
|----:|-----------|---|---|---|---|---|
| 1 | The system responds promptly to user actions. | | | | | |
| 2 | The system loads its pages and functions efficiently. | | | | | |
| 3 | Local storage and sync operations are processed within an acceptable period. | | | | | |
| 4 | Mobile scanning and review can be completed within an acceptable classroom period. | | | | | |
| 5 | The system maintains acceptable performance during normal use. | | | | | |

### E.3 Usability

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
|----:|-----------|---|---|---|---|---|
| 1 | The system interface is easy to understand. | | | | | |
| 2 | System functions are easy to locate and use. | | | | | |
| 3 | The information displayed by the system is understandable. | | | | | |
| 4 | Users can perform common tasks without excessive assistance. | | | | | |
| 5 | The system is convenient to use for its intended teacher purpose. | | | | | |

### E.4 Reliability

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
|----:|-----------|---|---|---|---|---|
| 1 | The system performs consistently during normal operation. | | | | | |
| 2 | The system maintains accurate roster and score information after save. | | | | | |
| 3 | The system correctly maintains teacher-owned class and result information. | | | | | |
| 4 | The system functions without frequent errors. | | | | | |
| 5 | The system can be relied upon for routine exam-day checking after setup. | | | | | |

### E.5 Security

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
|----:|-----------|---|---|---|---|---|
| 1 | The system restricts access according to user roles (teacher vs school administrator). | | | | | |
| 2 | User authentication provides appropriate protection. | | | | | |
| 3 | Academic information is protected from unauthorized access across teachers. | | | | | |
| 4 | The system provides appropriate controls for sensitive information (including keeping scan photos on the device). | | | | | |
| 5 | System activities can be monitored through appropriate records or account scoping. | | | | | |

### E.6 Maintainability

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
|----:|-----------|---|---|---|---|---|
| 1 | The system structure supports future maintenance. | | | | | |
| 2 | System modules can be modified without unnecessarily affecting other functions. | | | | | |
| 3 | Database structures are organized and manageable. | | | | | |
| 4 | System problems can be identified and investigated. | | | | | |
| 5 | The system can accommodate reasonable future enhancements. | | | | | |

### E.7 Portability

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
|----:|-----------|---|---|---|---|---|
| 1 | The teacher/administrator web portal can be accessed using modern web browsers. | | | | | |
| 2 | The system operates properly on the intended devices. | | | | | |
| 3 | The mobile application functions on the intended Android/iOS devices. | | | | | |
| 4 | System information remains accessible across supported interfaces (mobile and web) after sync. | | | | | |
| 5 | The system can be deployed within its intended school operational environment. | | | | | |

---

## APPENDIX F: ISO/IEC 25010 Evaluation Summary

The following table presents the results reported in Chapter 4 after forms are encoded. Until encoding is complete, cells remain Insert only.

| Software Quality Characteristic | Mean | Interpretation |
|---------------------------------|------|----------------|
| Functional Suitability | [Insert] | [Insert] |
| Performance Efficiency | [Insert] | [Insert] |
| Usability | [Insert] | [Insert] |
| Reliability | [Insert] | [Insert] |
| Security | [Insert] | [Insert] |
| Maintainability | [Insert] | [Insert] |
| Portability | [Insert] | [Insert] |
| Overall Software Quality | [Insert] | [Insert] |

---

## APPENDIX G: System Usability Scale (SUS) Questionnaire

**Instructions**

Please indicate how strongly you agree or disagree with each statement regarding your experience with the developed system.

| Rating | Meaning |
|-------:|---------|
| 5 | Strongly Agree |
| 4 | Agree |
| 3 | Neutral |
| 2 | Disagree |
| 1 | Strongly Disagree |

**SUS Items**

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
|----:|-----------|---|---|---|---|---|
| 1 | I think that I would like to use this system frequently. | | | | | |
| 2 | I found the system unnecessarily complex. | | | | | |
| 3 | I thought the system was easy to use. | | | | | |
| 4 | I think that I would need the support of a technical person to use this system. | | | | | |
| 5 | I found the various functions in this system were well integrated. | | | | | |
| 6 | I thought there was too much inconsistency in this system. | | | | | |
| 7 | I would imagine that most people would learn to use this system very quickly. | | | | | |
| 8 | I found the system very cumbersome to use. | | | | | |
| 9 | I felt very confident using the system. | | | | | |
| 10 | I needed to learn a lot of things before I could get going with this system. | | | | | |

**SUS Scoring Guide**

For positive-numbered items (1, 3, 5, 7, and 9), subtract 1 from the response.  
For negative-numbered items (2, 4, 6, 8, and 10), subtract the response from 5.  
Add the resulting scores and multiply the total by 2.5 to obtain the SUS score out of 100.

---

## APPENDIX H: System Usability Scale Results

| Evaluator Group | Participant Count | Mean SUS Score | Adjective Rating |
|-----------------|------------------:|---------------:|------------------|
| Engineering instructors | [Insert] | [Insert] | [Insert] |
| School administrators (if any) | [Insert] | [Insert] | [Insert] |
| IT / adviser experts (if any) | [Insert] | [Insert] | [Insert] |
| Overall evaluator mean | [Insert] | [Insert] | [Insert] |

**Overall SUS Result**

- Overall SUS Score: `[Insert] / 100`
- Adjective Rating: `[Insert]`
- Acceptability: `[Insert]`

The SUS results reported in Chapter 4 will be stated here only after forms are encoded. No substitute scores are inserted.

---

## APPENDIX I: Evaluator Group and Functional Testing Matrix

| Evaluator / User Group | Primary Functional Scope | Reported Result |
|------------------------|--------------------------|-----------------|
| IT / adviser experts (if any) | Authentication, security, role gates, and API sync | [Insert] |
| Engineering instructors | Prep - print - scan - review - sync - web results | [Insert] |
| School administrators (if any) | Teacher approval and school-scoped oversight | [Insert] |
| Total execution suite | Unit, integration, and system cases in Chapter 4 | Registry + 294/294 automated unit pass on recorded run |

---

## APPENDIX J: System Architecture and Design Documentation

### J.1 Use Case Diagram

**Figure J.1.** Use Case Diagram of the Developed Hybrid Offline-First OMR System  

*[Insert file: `paper_format_extract/figures/figure_4_11_use_case.png` or `D:\DOWNLOADS\figure_4_11_use_case.png`]*

The Use Case Diagram illustrates interactions among the Teacher and School Administrator and the system's major functions. A student is an examinee on the roster/sheet, not a logged-in actor.

### J.2 Context-Level Data Flow Diagram

**Figure J.2.** Context-Level (Level 0) Data Flow Diagram  

*[Insert file: `paper_format_extract/figures/figure_4_12_dfd_level0.png` or `D:\DOWNLOADS\figure_4_12_dfd_level0.png`]*

### J.3 Level 1 Data Flow Diagram

**Figure J.3.** Level 1 Data Flow Diagram  

*[Insert file: `paper_format_extract/figures/figure_4_13_dfd_level1.png` or `D:\DOWNLOADS\figure_4_13_dfd_level1.png`]*

### J.4 Entity-Relationship Diagram

**Figure J.4.** Entity-Relationship Diagram / Relational Schema  

*[Insert file: `paper_format_extract/figures/figure_4_14_erd_schema.png` or `D:\DOWNLOADS\figure_4_14_erd_schema.png`]*

---

## APPENDIX K: System Interface Documentation

### K.1 Teacher / Administrator Web Portal

#### K.1.1 Classes / Roster Desk

**Figure K.1.** Classes / Roster Interface  
*[Insert screenshot]*

Description: The Classes desk provides teachers with a view of sections and student roster records synchronized from the mobile workflow or prepared on the portal.

#### K.1.2 Prepare - Answer Keys

**Figure K.2.** Answer-Key Preparation Interface  
*[Insert screenshot]*

Description: The Prepare answer-key tools support shared and section-only keys and related exam preparation tasks.

#### K.1.3 Prepare - Print Sheets / OMR IDs

**Figure K.3.** Print Sheets / OMR ID Interface  
*[Insert screenshot]*

Description: Teachers can generate printable OMR materials and OMR ID lists for classroom use.

#### K.1.4 Results and Item Analysis

**Figure K.4.** Results / Item Analysis Interface  
*[Insert screenshot]*

Description: After sync, teachers can review scores and item analysis (difficulty and discrimination) on a larger screen and export records as needed.

#### K.1.5 Admin Access / Approval

**Figure K.5.** Admin Access Control Interface  
*[Insert screenshot]*

Description: School administrators approve pending teacher accounts and manage school-scoped access.

### K.2 Mobile Application

#### K.2.1 Sign-in / Offline PIN Unlock

**Figure K.6.** Mobile Sign-in / PIN Unlock  
*[Insert screenshot]*

Description: Teachers sign in online for bootstrap, then unlock daily with an offline PIN when connectivity is unavailable.

#### K.2.2 Scanner and Alignment Guidance

**Figure K.7.** Scanner View  
*[Insert screenshot]*

Description: The camera scanner captures printed sheets for native OpenCV reading against the sheet layout contract.

#### K.2.3 Review-before-save / Scan Confidence

**Figure K.8.** Review / Scan Confidence Interface  
*[Insert screenshot]*

Description: Flagged or auto-captured sheets can be reviewed using Safe / Check / Must review labels before scores are saved.

#### K.2.4 Exam Day Board

**Figure K.9.** Exam Day Board  
*[Insert screenshot]*

Description: Teachers track missing, review, done, and absent students for a section and subject during checking.

The interface features listed above correspond to the system features documented in Chapter 4.

---

## APPENDIX L: System Evaluation Consent and Respondent Information Sheet

**Participant Information**

You are invited to participate in the evaluation of the developed Hybrid Offline-First Optical Mark Recognition (OMR) Scanning System with Web-Based Grade Synchronization and Analytics. The purpose of the evaluation is to determine the functionality, software quality, usability, and operational performance of the developed system for teacher-side exam checking.

Participation in the evaluation is voluntary. The information collected will be used for academic and system-evaluation purposes.

**Confidentiality**

Information provided by participants shall be treated confidentially and shall only be used for the purposes of the study. Individual responses shall not be publicly identified in the presentation of the results.

**Evaluation Procedure**

Participants shall:

1. Receive an orientation regarding the developed system;
2. Access or observe the system functions relevant to their assigned role (instructor and/or school administrator);
3. Perform or observe designated system functions (for example: prepare, print, scan, review, sync, web results);
4. Complete the ISO/IEC 25010 evaluation questionnaire, when applicable;
5. Complete the System Usability Scale questionnaire, when applicable; and
6. Provide comments or observations regarding the system.

**Voluntary Participation**

Participation is voluntary. A participant may decline to answer any evaluation item or discontinue participation according to the applicable institutional research procedures.

*[Insert signature / consent block as required by the College]*

---

## APPENDIX M: Documentation of System Testing and Evaluation

### M.1 Testing Documentation

Insert photographs/screenshots documenting the following activities:

1. Unit testing;
2. Integration testing;
3. System testing;
4. Authentication testing;
5. Role-based access testing;
6. Roster / answer-key testing;
7. Print / scan testing;
8. Review-before-save testing;
9. Offline save and Sync Now testing;
10. Web results / item analysis testing;
11. Export testing; and
12. End-to-end exam-day path testing.

### M.2 Evaluation Documentation

Insert photographs showing the conduct of the system evaluation, subject to institutional research ethics and participant-consent requirements.

Suggested captions:

- Figure M.1. Orientation of System Evaluators
- Figure M.2. Demonstration of the Teacher Web Portal
- Figure M.3. Demonstration of the Mobile Application
- Figure M.4. Conduct of System Functionality Testing
- Figure M.5. Administration of the ISO/IEC 25010 Evaluation
- Figure M.6. Administration of the System Usability Scale

---

## APPENDIX N: Summary of System Evaluation Results

### N.1 Consolidated Results

| Evaluation Component | Result |
|----------------------|--------|
| Functional Requirements Verification | FR-01 to FR-11 verified; FR-12 out of scope |
| ISO/IEC 25010 Overall Mean | [Insert] |
| ISO/IEC 25010 Interpretation | [Insert] |
| Functionality Testing | Automated unit suite 294/294 pass; mapped registry cases passed on recorded run |
| Overall SUS Score | [Insert] / 100 |
| SUS Adjective Rating | [Insert] |
| SUS Acceptability | [Insert] |
| Exam-day continuity under poor Wi-Fi | Offline PIN unlock; local SQLite scoring after bootstrap (ST-503) |
| Timed checking improvement | [Insert only if timed trial logged] |
| Printed-sheet numeric accuracy | [Insert only if ST-401 / Table 4.6 logged] |
| Information management | Teacher-owned relational records (SQLite local; PostgreSQL synced rows) |
| Photograph handling | Scan photographs remain on the device; not uploaded |

### N.2 Overall Evaluation Statement

The consolidated evaluation results indicate that the developed hybrid offline-first OMR system satisfied the identified in-scope functional requirements (FR-01 to FR-11), achieved a full pass on the recorded automated unit suite (294/294) and mapped registry walkthroughs, and is ready for insertion of ISO/IEC 25010 and SUS composites after forms are encoded. Operational comparison emphasizes exam-day continuity through local save-then-sync and teacher review-before-save, without substituting invented speed or accuracy percentages for unlogged measurements.
