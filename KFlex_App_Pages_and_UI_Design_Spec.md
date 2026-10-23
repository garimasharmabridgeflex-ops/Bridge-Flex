# KFlex UK — Mobile & Web App UI/UX Master Design Specification
**Version:** 2.1 (October 2026)  
**Sector:** UK Early Years & Childcare (EYFS)  
**Target Platforms:** Flutter Mobile (iOS & Android) & Secure Desktop Web Admin Portal  
**Document Companion:** `KFlex_App_Pages_and_UI_Design_Spec.pdf` (saved at root)

---

## Executive Summary & Creative Brief

KFlex connects qualified Early Years practitioners (Nursery Nurses, Room Leaders, EYFS Specialists) with early years nurseries, pre-schools, and crèches across England and the United Kingdom.

### The Problem with the Current Design
The current palette of stark indigo (`#3F4CE0`) and aggressive hot coral (`#E0447A`) feels clinical, techy, and slightly generic ("meeh"). It lacks the warmth, approachability, and nurturing security expected in British early childhood care while maintaining compliance rigor (OFSTED ratios, DBS Update Service, HMRC PAYE payroll).

### The Strategic Direction
1. **Move Admin to Desktop Web:** Heavy compliance reviews, DBS verification, timesheet dispute resolution, and **HMRC Basic PAYE Tools CSV exports** belong on a dedicated Desktop Web Admin Portal (`/admin`), not on cramped mobile screens.
2. **Elevate Mobile UI for Practitioners & Nurseries:** Deliver warm, modern, high-trust mobile experiences with frictionless shift discovery, transparent rolled-up holiday pay (12.07%), and 1-tap timesheet submission.
3. **AI-Ready Screen Prompts:** Provide ready-to-copy design prompts for Midjourney, v0.dev, Galileo AI, and Figma AI for every single view.

---

## Modernized Color Palettes

### Option 1: Modern British Early Years (Recommended)
*Conveys nature, nurturing growth, safety, and Ofsted-grade compliance.*
- **Primary Forest Teal:** `#1E4B43` (Trust, grounding, early years warmth)
- **Honey Amber Accent:** `#EAA838` (Attention, active states, star ratings)
- **Nurture Peach:** `#F48B68` (Friendly accents, playful child-care touch)
- **Soft Alabaster Background:** `#F9FAF9` (Gentle on tired eyes during early morning shifts)
- **Slate Ink Text:** `#172321` (High-contrast WCAG AAA readability)

### Option 2: Warm Nordic Childhood & Care
*Approachable, modern Scandinavian early years aesthetic, calming for shift workers.*
- **Warm Terracotta:** `#C85A3D`
- **Soft Sage:** `#5A8B76`
- **Warm Oat Canvas:** `#FBF8F4`
- **Muted Olive:** `#344B3F`
- **Charcoal Text:** `#1F2421`

### Option 3: High-Trust Healthcare & Institutional Trust
*Emphasis on DBS vetting rigor, payroll precision, and corporate childcare groups.*
- **Oxford Navy:** `#1B2A4A`
- **Marigold Accent:** `#F2A900`
- **Mint Success:** `#10B981`
- **Pearl Canvas:** `#F8FAFC`
- **Deep Slate:** `#0F172A`

---

## Complete Mobile Screen Catalog & AI Design Prompts

### 1. Splash & App Entry Screen (`/splash`)
- **Persona:** Practitioners & Nursery Managers
- **Goal:** Authenticate session, check feature flags and minimum version code, route to Home or Onboarding.
- **Key Elements:** Animated brand mark, warm welcoming tagline, subtle loading shimmer.
- **AI Design Prompt:**
  > `Modern clean mobile splash screen for UK early years nursery staffing app 'KFlex'. Centered elegant minimalist logo featuring interlocking leaf and bridge symbol. Forest teal (#1E4B43) and honey gold (#EAA838) accents on a soft alabaster warm white background (#F9FAF9). Subtle typography reading 'KFlex: Early Years Staffing, Simplified'. Smooth micro-shimmer loading bar at bottom. iOS and Android UI kit, 8k resolution, minimalist, warm and trustworthy.`

### 2. Role Selection Screen (`/role-select`)
- **Persona:** New Unregistered Users
- **Goal:** Choose between Early Years Practitioner vs Nursery Group Manager.
- **Key Elements:** Two large elevated touch cards with warm illustrations, selection highlights, bottom sign-in link.
- **AI Design Prompt:**
  > `Dual-role selection screen for UK childcare mobile app. Two large rounded touch cards on soft oat background. Top card shows 'Childcare Practitioner' with badge 'Level 2, 3 & Qualified Nursery Nurses' and pay indicator 'Earn up to £18.50/hr'. Bottom card shows 'Nursery / Early Years Setting' with badge 'Emergency cover & long-term staff'. Selected card has elegant warm emerald border (#1E4B43) with soft shadow. Clean typography, Plus Jakarta Sans, Figma UI design, award-winning healthcare mobile design.`

### 3. Authentication: Sign In Screen (`/sign-in`)
- **Persona:** Returning Users
- **Goal:** Fast, secure login with email/password or biometric Google/Apple auth.
- **Key Elements:** Email input, password with eye toggle, forgot password link, pill-shaped primary CTA, Apple & Google social sign-in buttons.
- **AI Design Prompt:**
  > `Crisp, welcoming login screen for UK nursery staffing app. Forest teal primary button (#1E4B43) with rounded pill radius. Email input with email icon, password input with eye icon and forgot link. 'Sign In' button with soft drop shadow. Social login pills for Apple and Google. Soft warm cream background, subtle child-friendly geometric shapes in header illustration. Clean mobile interface, modern Material 3, accessible contrast ratios.`

### 4. Authentication: Sign Up Screen (`/sign-up`)
- **Persona:** New Users
- **Goal:** Create account with full name, email, UK phone number (+44), strong password, and terms acceptance.
- **Key Elements:** Password strength meter (4 color bars), UK phone field with flag, interactive Terms checkbox.
- **AI Design Prompt:**
  > `Modern registration screen for UK education app. Step indicator showing step 1 of 3. Full name, UK phone number with +44 flag picker, email, password strength indicator with 4 progressive color bars (weak red to strong forest green). Interactive checkbox with blue-underlined UK terms link. Warm cream surface, high-contrast dark slate text, pill-shaped primary action button.`

### 5. Password Recovery Screens (`/forgot-password` & `/change-password`)
- **Persona:** Users needing credential recovery
- **Goal:** Request Firebase password reset link or update credentials.
- **Key Elements:** Friendly reassurance text, email input, 'Send Recovery Link' button, success confirmation card with 60s cooldown timer.
- **AI Design Prompt:**
  > `Minimalist password reset screen for mobile app. Friendly illustration of an envelope with a security shield. Input field for registered email with mail icon. Primary button 'Send Instructions'. Success card state showing green tick badge, instructions to check spam folder, and countdown resend timer. Soft alabaster background, warm emerald accents, clean typography.`

### 6. Practitioner Onboarding Wizard (`/onboarding/staff`)
- **Persona:** Newly Registered Practitioners
- **Goal:** Capture EYFS qualification (L2, L3, L4+), years of experience, home postcode, and travel radius.
- **Key Elements:** Segmented progress bar, interactive qualification chips, UK postcode field with interactive radius slider (5 to 25 miles).
- **AI Design Prompt:**
  > `Step-by-step onboarding wizard for UK nursery nurses. Top has 3 pill progress dots. Clean chip selector grid for UK Childcare Qualifications: Level 2 Diploma, Level 3 Early Years Educator, Level 4/Degree, Unqualified Assistant. Postcode entry field with interactive travel radius slider (5 miles, 10 miles, 15 miles) with live map preview circle. Modern Flutter UI design, soft warm palette, accessible typography.`

### 7. Nursery Group Onboarding Wizard (`/onboarding/nursery`)
- **Persona:** Nursery Owners & Room Managers
- **Goal:** Collect Companies House number, billing email/contact, initial branch address, and Ofsted URN.
- **Key Elements:** 3-step card wizard, Companies House auto-lookup, VAT toggle, 14-day free trial reassurance badge.
- **AI Design Prompt:**
  > `Executive 3-step nursery registration screen for UK nursery directors. Card-based form with company registration number input, company name, Ofsted URN field with informational tooltip, billing email and invoice address. Bottom summary shows '14-Day Free Trial will activate upon approval'. Forest green and warm gold accents, professional B2B mobile UX, clean card elevation.`

### 8. Versioned Terms Acceptance Sheet (`/terms-acceptance`)
- **Persona:** All Users upon legal update
- **Goal:** Mandatory audit-compliant acceptance of versioned terms and staff handbook.
- **Key Elements:** Draggable bottom sheet, scrollable terms container, 'What Changed in v2.1' callout box, locked acceptance checkbox until scrolled.
- **AI Design Prompt:**
  > `Modern bottom sheet modal for legal policy acceptance. Draggable top notch. Clean card with scrollable legal text container. Prominent alert box highlighting 'What Changed in Version 2.1 (October 2026): Clearer timesheet dispute windows and statutory rolled-up holiday pay breakdown'. Checkbox 'I have read and agree to the KFlex Terms'. Primary emerald button. Material 3 bottom sheet design.`

### 9. Browse Shifts: Map & List View (`/shifts`)
- **Persona:** Early Years Practitioners
- **Goal:** Explore open shifts nearby, filter by qualification, rate, distance, and toggle List vs Map view.
- **Key Elements:** Sticky filter chips, interactive map with custom pins, shift cards showing nursery name, room type, hours, net payable time, and statutory holiday pay split.
- **AI Design Prompt:**
  > `Top-tier job discovery feed for UK nursery nurses. Top sticky header with horizontal scrolling filter chips: 'Tomorrow', 'This Weekend', 'Level 3 Only', '< 5 Miles'. Shift feed showing elevated cards with rounded corners. Each card features: nursery thumbnail, branch name, distance pill badge '1.8 mi', room type tag 'Baby Room 0-2 yrs', shift duration '8:00 AM - 5:00 PM (1h unpaid break)', bold highlighted pay badge '£18.00/hr (£16.06 + £1.94 Holiday Pay)'. Floating bottom navigation bar. Vibrant, warm, ultra-clean mobile UI.`

### 10. Shift Details Screen (`/shifts/:id`)
- **Persona:** Practitioners evaluating a shift
- **Goal:** In-depth review of shift location, room duties, dress code, break policies, and one-tap application.
- **Key Elements:** Nursery classroom photo, Ofsted rating pill, map directions button, pay formula breakdown (Basic + 12.07% Holiday Pay), duties checklist, sticky 'Apply for Shift' bar.
- **AI Design Prompt:**
  > `Detailed shift overview screen in mobile app. Top header image of a bright, modern UK nursery classroom with 'Ofsted Outstanding' pill badge. Information cards: 'Location & Parking', 'Hours: 08:30 - 17:30 (30 min unpaid break = 8.5 payable hours)', 'Pay Breakdown: Basic Rate £15.17/hr + 12.07% Rolled-up Holiday Pay £1.83/hr = Total £17.00/hr'. Requirements checklist with green ticks. Sticky bottom bar with 'Apply for Shift' button. Forest green and honey accents, ultra-legible.`

### 11. My Shifts: Schedule & History (`/my-shifts`)
- **Persona:** Practitioners and Nursery Managers
- **Goal:** Track upcoming shifts, live countdown, pending timesheets, and completed booking history.
- **Key Elements:** Segmented tabs (Upcoming, In Progress, Pending Timesheet, Completed), countdown timer, quick actions to call manager or submit timesheet.
- **AI Design Prompt:**
  > `Schedule and shift tracking screen for childcare workers. Segmented top control: 'Upcoming (3)', 'Completed (12)'. Upcoming card has a large countdown timer 'Starts in 2 hours 15 mins', address with navigation icon, manager contact button, and 'Check In / Timesheet' button. Clean card layout with drop shadows, warm cream background, subtle micro-badges.`

### 12. Submit Timesheet Sheet (`/shifts/:id/timesheet`)
- **Persona:** Practitioners completing a shift
- **Goal:** Input actual hours, select break deduction (0m, 30m, 60m), preview net payable earnings, and submit for nursery approval.
- **Key Elements:** Draggable modal sheet, time pickers, segmented break pills, live earnings calculator, 48-hour auto-approval policy notice.
- **AI Design Prompt:**
  > `Interactive timesheet entry bottom sheet in mobile app. Start time wheel picker (08:00) and finish time picker (16:30). Horizontal break deduction selector pills: 'None', '30 mins (Standard)', '60 mins'. Dynamic calculation box displaying: Total Hours: 8.5h | Unpaid Break: 0.5h | Net Payable: 8.0h | Estimated Gross: £136.00. Input box for practitioner notes ('Covered late pickup until 16:30'). Submit button with forest teal background.`

### 13. Practitioner Earnings & Payslips (`/payroll/earnings`)
- **Persona:** Practitioners monitoring pay
- **Goal:** View monthly earnings, inspect statutory rolled-up holiday pay accumulator (12.07%), and download official HMRC PAYE payslips.
- **Key Elements:** Hero balance card with teal gradient, sub-cards for Basic Pay and Accrued Holiday Pay, weekly payslip history list with PDF download button.
- **AI Design Prompt:**
  > `Financial earnings and payslip dashboard for UK healthcare/childcare workers. Hero card with dark teal gradient: 'October 2026 Earnings: £1,842.50'. Two sub-metrics cards: 'Basic Wages: £1,644.06' and 'Accrued Holiday Pay (12.07%): £198.44'. List of weekly payslips with download icon, pay date, gross amount, and HMRC PAYE badge. Clean, high-trust fintech aesthetic, warm gold accents.`

### 14. Post Shift Wizard (`/shifts/post`)
- **Persona:** Nursery Managers
- **Goal:** Post an open shift in under 60 seconds with branch selection, room, qualification requirement, and live rate card cost preview.
- **Key Elements:** Branch selector, date/time spinners, room age group selector, qualification requirement pills (L2, L3, L4+), live cost calculator (+VAT indicator).
- **AI Design Prompt:**
  > `Fast-action shift posting screen for nursery directors. Clean step form on warm alabaster background. Branch selector card with pin icon. Time picker with start/end visual timeline. Qualification requirement selector pills with distinct color tags: 'Level 2 Qualified', 'Level 3 Qualified (Required)', 'Level 4 / Room Leader'. Cost preview container: '8 hours @ £22.00/hr = £176.00 + VAT'. Big primary CTA 'Broadcast to Qualified Staff'.`

### 15. Nursery Invoices & Subscription (`/billing/invoices`)
- **Persona:** Nursery Owners & Finance Directors
- **Goal:** Monitor 14-day free trial countdown, view active membership plan, inspect weekly invoices (`INV-YYYY-XXXX`), and view bank transfer details.
- **Key Elements:** Free trial countdown ring card, plan cards (Standard £199, Premium £299, PAYG £9.99), invoice history list, bank transfer modal popup.
- **AI Design Prompt:**
  > `B2B billing and invoice management screen for nursery groups. Top card shows '14-Day Free Trial: 8 days remaining' with progress countdown ring. Subscription tier card displaying 'Standard Plan — £199/month ex-VAT'. Weekly invoice table with invoice numbers (INV-2026-0042), dates, amounts (£412.50), and payment status badges. Button 'Pay via Bacs / Bank Transfer' displaying pop-up modal with bank account details.`

### 16. DBS & Document Upload (`/documents/dbs`)
- **Persona:** Practitioners submitting compliance records
- **Goal:** Upload Enhanced DBS certificate, enter 12-digit number, grant Update Service consent, and upload photo ID.
- **Key Elements:** Document viewfinder with corner guides, certificate number field, Update Service toggle, AES-256 encryption trust badge.
- **AI Design Prompt:**
  > `Mobile document scanner and verification screen. Camera viewfinder container with dashed rounded border, document icon, and 'Take Photo or Choose PDF' button. Certificate guidelines box: 'Must be Enhanced Child Workforce DBS issued within 3 years or registered on the Update Service'. Input field for 12-digit certificate number. Trust badge: 'End-to-End Encrypted & GDPR Compliant'. Submit button in dark teal.`

### 17. Training & EYFS CPD Hub (`/training`)
- **Persona:** Practitioners advancing credentials
- **Goal:** Watch mandatory UK childcare modules (Safeguarding L2, Pediatric First Aid, EYFS Framework), complete quizzes, and unlock badges.
- **Key Elements:** Module progress cards with completion bars, video player modal, 5-question multiple choice quiz with instant feedback.
- **AI Design Prompt:**
  > `E-learning training module list for nursery workers. Header 'EYFS Continuing Professional Development'. Cards for training courses: 'Safeguarding Children in Early Years (2026 Refresher)' with 85% progress bar, 'Pediatric First Aid Basics' with green tick 'Certified'. Clean card UI with play icon, video duration badge, and 'Start Quiz' button. Clean educational styling, inspiring and warm.`

### 18. In-App Messaging (`/chat` & `/chat/:id`)
- **Persona:** Booked Practitioners & Nursery Managers
- **Goal:** Secure real-time communication regarding shift arrival, room assignment, or delay notifications.
- **Key Elements:** Conversation list with unread pills, chat screen with shift summary banner, bubble stream, photo attachment, double-check delivery ticks.
- **AI Design Prompt:**
  > `Clean, professional messaging screen between nursery manager and temporary staff. Top bar displays nursery name 'Little Acorns Nursery' and confirmed shift pill 'Tomorrow 08:00 - 16:30'. Chat bubbles with soft rounded corners, timestamps, and delivered double-check marks. Input bar with photo attachment icon and send button. Safe, polite, distraction-free interface.`

### 19. Profile, Reviews & Branches (`/profile` & `/profile/branches`)
- **Persona:** Practitioners & Nursery Managers
- **Goal:** Manage profile details, emergency contact, view ratings and written reviews from nurseries, and manage multi-branch locations.
- **Key Elements:** Hero avatar with verified DBS badge, star rating card ('4.9 ★'), feedback carousel, branch management list for nurseries.
- **AI Design Prompt:**
  > `User profile screen in mobile app. Circular profile avatar with green 'DBS Verified' badge. Star rating card: '4.9 out of 5 stars based on 28 completed shifts'. Written feedback carousel from nursery managers. Settings and documents summary below. Clean, warm, high-credibility profile layout.`

### 20. Settings & Account Deletion (`/settings` & `/settings/delete-account`)
- **Persona:** All Users
- **Goal:** Preferences, notifications, theme toggles, legal links, and GDPR-compliant account deletion.
- **Key Elements:** Grouped settings tiles, Dark Mode switch, red outline card for account deletion with UK statutory payroll retention notices.
- **AI Design Prompt:**
  > `App settings screen with clean grouped list items on warm background. Toggle switches for notifications and theme. Bottom section with red outline card for 'Delete Account & Personal Data'. Account deletion confirmation screen showing warning checklist regarding tax and payroll data retention under UK HMRC law. High accessibility, clean Material 3 design.`

---

## Desktop Web Admin Portal Transition Specification

All regulatory, payroll, invoicing, and vetting tasks are transitioned to the dedicated Desktop Web Admin Portal at `/admin` (Firebase Hosting).

### 1. Admin Authentication & Role Gate (`/admin/login`)
- **Goal:** Secure MFA/2FA sign-in verifying `AdminRole` claims before unlocking dashboard routes.
- **AI Prompt:** `Desktop web login screen for UK childcare staffing admin platform. Split layout with deep forest teal left panel (#1E4B43) and clean white login card on right. 2FA verification code input, secure badge, session timer, enterprise SaaS aesthetic.`

### 2. Executive Operations Dashboard (`/admin/dashboard`)
- **Goal:** High-level platform health: Total Nurseries, Total Staff, Open Shifts, Booked Shifts, Pending Documents, Unsettled Invoices, and Suspended Users.
- **AI Prompt:** `Executive desktop admin dashboard for early years platform. Top row of 6 clean KPI metric cards with subtle icons and colored badges. Middle section showing live urgent approval queue table. Forest teal and soft slate theme, modern SaaS UI.`

### 3. Practitioner Compliance & Vetting Hub (`/admin/vetting`)
- **Goal:** Side-by-side document verification: Enhanced DBS, Passport/ID, DBS Update Service verification toggle, and one-click Approve / Request Docs / Reject.
- **AI Prompt:** `Desktop compliance review console with split screen. Left side: practitioner profile and DBS verification form. Right side: high-resolution document viewer showing DBS certificate with zoom controls and approval/rejection action bar.`

### 4. Nursery Group & Branch Approval Console (`/admin/nurseries`)
- **Goal:** Companies House lookup, branch inspection, and one-click approval triggering the 14-day free trial.
- **AI Prompt:** `B2B nursery management desktop admin interface. Data table with columns for Nursery Name, Company Number, Branches, Signup Date, Status Pill, and Actions. Clean modal for approving nursery registration and triggering free trial.`

### 5. Timesheet Oversight & Escalation Console (`/admin/timesheets`)
- **Goal:** National timesheet table, auto-escalation alert badge (>48h without nursery approval), dispute resolution drawer, manual approval override.
- **AI Prompt:** `Desktop administrative timesheet dispute and approval table. Amber warning pills for auto-escalated shifts (>48h). Side drawer showing clock-in timestamps, break deductions, and practitioner notes with manual override approval button.`

### 6. HMRC Basic PAYE Payroll & CSV Export Hub (`/admin/payroll`)
- **Goal:** Run statutory payroll, inspect Gross vs Basic vs 12.07% Rolled-up Holiday Pay breakdowns, and **download official HMRC Basic PAYE Tools CSV** with 1-click.
- **AI Prompt:** `Payroll management desktop dashboard for UK employer. Period selector 'Week 42 - Oct 2026'. Summary boxes displaying Gross Pay £14,250, Basic Pay £12,715.27, Rolled-up Holiday Pay (12.07%) £1,534.73. Large primary button 'Export HMRC Basic PAYE Tools CSV' with file download icon. High-trust fintech data table.`

### 7. Weekly Billing & Bank Settlement Hub (`/admin/invoices`)
- **Goal:** Reconcile sequential invoices (`INV-YYYY-XXXX`), verify Bacs bank transfers, click 'Mark Paid' to update ledger and emit outbox confirmation.
- **AI Prompt:** `Desktop invoice reconciliation and bank transfer matching table for B2B platform. Sequential invoice numbers INV-2026-0042, nursery names, amount in GBP (£), payment status badges. Action button 'Mark Paid via Bank Transfer' with modal for entering bank transaction reference.`

### 8. Immutable Audit Trail Console (`/admin/audit`)
- **Goal:** Tamper-evident, append-only security log of all administrative actions with actor UID, timestamps, and before/after diffs.
- **AI Prompt:** `Security audit log desktop screen for regulated platform. Monospace timestamps, actor badges, action tags (VETTING_APPROVED, PAYROLL_GENERATED), expandable JSON diff viewer showing before and after states. Dark slate and teal accents.`

---

## Design System Tokens for AI Image / Code Generation

- **Typography:** Plus Jakarta Sans or Inter. Display (24-28pt Bold), Titles (16-18pt SemiBold), Body (14pt Regular, 1.5 line height), Badges (11-12pt Medium).
- **Border Radii:** Cards: 16px. Primary CTAs: 999px (Pill). Inputs: 12px. Modals: 24px top radius.
- **Elevation:** Level 1: `0 2px 4px rgba(18, 28, 24, 0.04), 0 8px 16px rgba(18, 28, 24, 0.06)`. Never use harsh black drop shadows.
- **Photography:** Authentic British early years settings: bright natural timber, cozy reading corners, diverse qualified practitioners in smart polo shirts.
- **Accessibility:** WCAG AAA compliance, minimum 4.5:1 text contrast, never rely on color alone for critical status.
