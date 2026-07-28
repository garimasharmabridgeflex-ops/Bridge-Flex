import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { newTestEnv, seed } from "./helpers.js";

// Covers ARCHITECTURE.md v2 §2/§3/§4 — no separate bookings collection,
// status/bookedStaffId frozen from every client, open-vs-booked read
// visibility.
describe("shifts rules", () => {
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
      await setDoc(doc(db, "shifts/open1"), {
        nurseryId: "nurseryA",
        title: "Morning cover",
        date: "2026-07-23",
        status: "open",
        bookedStaffId: null,
        payRate: 15,
        paymentStatus: "not_required",
      });
      await setDoc(doc(db, "shifts/booked1"), {
        nurseryId: "nurseryA",
        title: "Afternoon cover",
        date: "2026-07-23",
        status: "booked",
        bookedStaffId: "staffA",
        payRate: 15,
        paymentStatus: "not_required",
      });
    });
  });

  it("any authenticated staff can read an open shift", async () => {
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    await assertSucceeds(getDoc(doc(asStaffB, "shifts/open1")));
  });

  it("the nursery and booked staff can fully read a booked shift", async () => {
    const asNursery = testEnv.authenticatedContext("nurseryA").firestore();
    const asBookedStaff = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(getDoc(doc(asNursery, "shifts/booked1")));
    await assertSucceeds(getDoc(doc(asBookedStaff, "shifts/booked1")));
  });

  it("a third-party staff member cannot read a booked shift", async () => {
    const asOtherStaff = testEnv.authenticatedContext("staffB").firestore();
    await assertFails(getDoc(doc(asOtherStaff, "shifts/booked1")));
  });

  it("a client cannot set shifts.bookedStaffId directly", async () => {
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    await assertFails(
      updateDoc(doc(asStaffB, "shifts/open1"), { bookedStaffId: "staffB", status: "booked" })
    );
  });

  it("the owning nursery cannot set bookedStaffId on their own open shift either", async () => {
    const asNursery = testEnv.authenticatedContext("nurseryA").firestore();
    await assertFails(
      updateDoc(doc(asNursery, "shifts/open1"), { bookedStaffId: "staffA", status: "booked" })
    );
  });

  it("the owning nursery can edit an open shift's editable fields", async () => {
    const asNursery = testEnv.authenticatedContext("nurseryA").firestore();
    await assertSucceeds(updateDoc(doc(asNursery, "shifts/open1"), { title: "Updated title" }));
  });

  it("the owning nursery cannot edit a shift once it's booked", async () => {
    const asNursery = testEnv.authenticatedContext("nurseryA").firestore();
    await assertFails(updateDoc(doc(asNursery, "shifts/booked1"), { title: "Nope" }));
  });
});
