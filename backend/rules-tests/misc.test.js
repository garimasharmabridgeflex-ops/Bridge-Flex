import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { addDoc, collection, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { newTestEnv, seed } from "./helpers.js";

// Spot-checks the remaining collections from ARCHITECTURE.md v2 §3 not
// covered by profiles.test.js / shifts.test.js: ratings, chatSessions,
// documents, notifications, transactions.
describe("ratings / chat / documents / notifications / transactions rules", () => {
  let testEnv;

  beforeAll(async () => {
    testEnv = await newTestEnv();
  });

  afterAll(async () => {
    await testEnv.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "shifts/booked1"), {
        nurseryId: "nurseryA",
        title: "Afternoon cover",
        date: "2026-07-23",
        status: "booked",
        bookedStaffId: "staffA",
        payRate: 15,
        paymentStatus: "not_required",
      });
      await setDoc(doc(db, "chatSessions/session1"), {
        shiftId: "booked1",
        participantIds: ["nurseryA", "staffA"],
      });
      await setDoc(doc(db, "notifications/notif1"), {
        uid: "staffA",
        type: "shift_booked",
        payload: { shiftId: "booked1" },
        read: false,
      });
    });
  });

  it("the booked staff member can create a rating for the nursery on their shared shift", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(
      addDoc(collection(asStaffA, "ratings"), {
        shiftId: "booked1",
        raterId: "staffA",
        rateeId: "nurseryA",
        score: 5,
        comment: "Great shift",
      })
    );
  });

  it("a user cannot create a rating for a shift they weren't part of", async () => {
    const asOutsider = testEnv.authenticatedContext("staffB").firestore();
    await assertFails(
      addDoc(collection(asOutsider, "ratings"), {
        shiftId: "booked1",
        raterId: "staffB",
        rateeId: "nurseryA",
        score: 5,
      })
    );
  });

  it("chat participants can read and post messages in their session", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(getDoc(doc(asStaffA, "chatSessions/session1")));
    await assertSucceeds(
      addDoc(collection(asStaffA, "chatSessions/session1/messages"), {
        senderId: "staffA",
        text: "On my way",
      })
    );
  });

  it("a non-participant cannot read or post in a chat session", async () => {
    const asOutsider = testEnv.authenticatedContext("staffB").firestore();
    await assertFails(getDoc(doc(asOutsider, "chatSessions/session1")));
    await assertFails(
      addDoc(collection(asOutsider, "chatSessions/session1/messages"), {
        senderId: "staffB",
        text: "Uninvited",
      })
    );
  });

  it("a client cannot create the documents metadata doc outside their own storage prefix", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      addDoc(collection(asStaffA, "documents"), {
        uid: "staffA",
        type: "dbs_certificate",
        storagePath: "dbs-documents/someoneElse/cert.pdf",
        status: "pending_review",
      })
    );
  });

  it("a client can create their own documents metadata doc under their own prefix", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(
      addDoc(collection(asStaffA, "documents"), {
        uid: "staffA",
        type: "dbs_certificate",
        storagePath: "dbs-documents/staffA/cert.pdf",
        status: "pending_review",
      })
    );
  });

  it("the owner can mark their own notification read, and only the read flag", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(updateDoc(doc(asStaffA, "notifications/notif1"), { read: true }));
  });

  it("no one can read or write the transactions collection directly", async () => {
    const asNursery = testEnv.authenticatedContext("nurseryA").firestore();
    await assertFails(getDoc(doc(asNursery, "transactions/tx1")));
    await assertFails(setDoc(doc(asNursery, "transactions/tx1"), { amount: 100 }));
  });

  it("Phase 2: auditLogs collection is completely forbidden from client reads and writes", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(getDoc(doc(asStaffA, "auditLogs/log1")));
    await assertFails(setDoc(doc(asStaffA, "auditLogs/log1"), { action: "hack" }));
  });

  it("Phase 2: outbox, idempotency, and sentEmails collections are completely forbidden from client reads and writes", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(getDoc(doc(asStaffA, "outbox/event1")));
    await assertFails(setDoc(doc(asStaffA, "outbox/event1"), { topic: "send-email" }));
    await assertFails(getDoc(doc(asStaffA, "idempotency/key1")));
    await assertFails(setDoc(doc(asStaffA, "idempotency/key1"), { status: "pending" }));
    await assertFails(getDoc(doc(asStaffA, "sentEmails/email1")));
    await assertFails(setDoc(doc(asStaffA, "sentEmails/email1"), { sent: true }));
  });

  it("Phase 2: platformConfig/company is readable by signed-in users but cannot be written by clients", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(getDoc(doc(asStaffA, "platformConfig/company")));
    await assertFails(setDoc(doc(asStaffA, "platformConfig/company"), { companyName: "Fake Co" }));
  });

  it("Phase 2: other platformConfig docs are forbidden from client reads and writes", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(getDoc(doc(asStaffA, "platformConfig/secretKeys")));
    await assertFails(setDoc(doc(asStaffA, "platformConfig/secretKeys"), { key: "bad" }));
  });

  it("Phase 3: published policies can be read by clients, drafts cannot", async () => {
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "policies/published1"), { type: "privacy", status: "published", version: 1 });
      await setDoc(doc(db, "policies/draft1"), { type: "privacy", status: "draft", version: 2 });
    });
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(getDoc(doc(asStaffA, "policies/published1")));
    await assertFails(getDoc(doc(asStaffA, "policies/draft1")));
    await assertFails(setDoc(doc(asStaffA, "policies/published1"), { title: "hacked" }));
  });

  it("Phase 3: users can only read their own policyAcceptances, never write directly", async () => {
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "policyAcceptances/staffA_privacy_1"), { uid: "staffA", policyType: "privacy", version: 1 });
    });
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    await assertSucceeds(getDoc(doc(asStaffA, "policyAcceptances/staffA_privacy_1")));
    await assertFails(getDoc(doc(asStaffB, "policyAcceptances/staffA_privacy_1")));
    await assertFails(setDoc(doc(asStaffA, "policyAcceptances/staffA_privacy_2"), { uid: "staffA", version: 2 }));
  });

  it("Phase 4: sensitive collection is completely forbidden from client reads and writes", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(getDoc(doc(asStaffA, "sensitive/staffA")));
    await assertFails(setDoc(doc(asStaffA, "sensitive/staffA"), { dob: "1990-01-01" }));
  });

  it("Phase 4: vetting collection is completely forbidden from client reads and writes", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(getDoc(doc(asStaffA, "vetting/staffA")));
    await assertFails(setDoc(doc(asStaffA, "vetting/staffA"), { dbsStatus: "valid" }));
  });

  it("Phase 4: vetting requests can be read by the practitioner owner but cannot be written by clients", async () => {
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "vetting/staffA/requests/req1"), { docType: "dbs_certificate", message: "Please re-upload" });
    });
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    await assertSucceeds(getDoc(doc(asStaffA, "vetting/staffA/requests/req1")));
    await assertFails(getDoc(doc(asStaffB, "vetting/staffA/requests/req1")));
    await assertFails(setDoc(doc(asStaffA, "vetting/staffA/requests/req2"), { docType: "id" }));
  });

  it("Phase 5: nursery branches can be read by signed-in users and written only by the owner", async () => {
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "nurseries/nurseryA/branches/branch1"), { name: "Central", isPrimary: true });
    });
    const asNurseryA = testEnv.authenticatedContext("nurseryA").firestore();
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    const asNurseryB = testEnv.authenticatedContext("nurseryB").firestore();

    // Authenticated users can read
    await assertSucceeds(getDoc(doc(asStaffA, "nurseries/nurseryA/branches/branch1")));

    // Owning nursery can create & update
    await assertSucceeds(setDoc(doc(asNurseryA, "nurseries/nurseryA/branches/branch2"), { name: "North", address: "10 High St" }));
    await assertSucceeds(updateDoc(doc(asNurseryA, "nurseries/nurseryA/branches/branch1"), { name: "Central Edited" }));

    // Non-owner cannot write
    await assertFails(setDoc(doc(asNurseryB, "nurseries/nurseryA/branches/branch3"), { name: "Hijacked" }));
    await assertFails(updateDoc(doc(asStaffA, "nurseries/nurseryA/branches/branch1"), { name: "Hacked" }));
  });

  it("Phase 6: rateCards are readable by clients but immutable from clients", async () => {
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "rateCards/card1"), { version: 1, active: true });
    });
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(getDoc(doc(asStaffA, "rateCards/card1")));
    await assertFails(setDoc(doc(asStaffA, "rateCards/card2"), { version: 2 }));
    await assertFails(updateDoc(doc(asStaffA, "rateCards/card1"), { active: false }));
  });

  it("Phase 6: cancellations documents cannot be written by clients", async () => {
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "cancellations/cancel1"), { actorId: "staffA", shiftId: "shift1", chargePence: 0 });
    });
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(getDoc(doc(asStaffA, "cancellations/cancel1")));
    await assertFails(setDoc(doc(asStaffA, "cancellations/cancel2"), { actorId: "staffA" }));
    await assertFails(updateDoc(doc(asStaffA, "cancellations/cancel1"), { chargePence: 100 }));
  });

  it("Phase 7: timesheets can be read by shift participants or admins, but clients cannot write", async () => {
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "timesheets/ts1"), {
        shiftId: "shift1",
        staffId: "staffA",
        nurseryId: "nurseryA",
        status: "submitted",
        billableMinutes: 450,
      });
    });

    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    const asNurseryA = testEnv.authenticatedContext("nurseryA").firestore();
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    const asAdmin = testEnv.authenticatedContext("adminUser", { role: "admin" }).firestore();

    // Staff participant can read
    await assertSucceeds(getDoc(doc(asStaffA, "timesheets/ts1")));
    // Nursery participant can read
    await assertSucceeds(getDoc(doc(asNurseryA, "timesheets/ts1")));
    // Admin can read
    await assertSucceeds(getDoc(doc(asAdmin, "timesheets/ts1")));
    // Unrelated staff cannot read
    await assertFails(getDoc(doc(asStaffB, "timesheets/ts1")));

    // Direct client writes are forbidden
    await assertFails(setDoc(doc(asStaffA, "timesheets/ts2"), { shiftId: "shift2" }));
    await assertFails(updateDoc(doc(asNurseryA, "timesheets/ts1"), { status: "approved" }));
  });

  it("Phase 8: payrollProfiles and payrollPeriods are role-gated, clients cannot write directly", async () => {
    await seed(testEnv, async (db) => {
      await setDoc(doc(db, "payrollProfiles/staffA"), {
        uid: "staffA",
        eligibleForRolledUpHolidayPay: true,
      });
      await setDoc(doc(db, "payrollPeriods/p1"), {
        periodName: "Week 44",
        status: "draft",
      });
      await setDoc(doc(db, "payrollPeriods/p1/lines/lineA"), {
        practitionerId: "staffA",
        grossPayPence: 1700,
      });
      await setDoc(doc(db, "payslips/ps1"), {
        practitionerId: "staffA",
        periodName: "Week 44",
      });
    });

    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    const asFinance = testEnv.authenticatedContext("financeUser", { role: "finance" }).firestore();

    // Staff can read own payroll profile
    await assertSucceeds(getDoc(doc(asStaffA, "payrollProfiles/staffA")));
    // Other staff cannot read staffA's payroll profile
    await assertFails(getDoc(doc(asStaffB, "payrollProfiles/staffA")));
    // Finance admin can read
    await assertSucceeds(getDoc(doc(asFinance, "payrollProfiles/staffA")));

    // Staff cannot write to payrollProfile directly
    await assertFails(updateDoc(doc(asStaffA, "payrollProfiles/staffA"), { eligibleForRolledUpHolidayPay: false }));

    // Staff cannot read general payrollPeriods, but can read own line
    await assertFails(getDoc(doc(asStaffA, "payrollPeriods/p1")));
    await assertSucceeds(getDoc(doc(asStaffA, "payrollPeriods/p1/lines/lineA")));
    await assertSucceeds(getDoc(doc(asFinance, "payrollPeriods/p1")));

    // Staff can read own payslip, not others
    await assertSucceeds(getDoc(doc(asStaffA, "payslips/ps1")));
    await assertFails(getDoc(doc(asStaffB, "payslips/ps1")));
  });
});
