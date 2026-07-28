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
});
