import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { newTestEnv, seed } from "./helpers.js";

// Covers ARCHITECTURE.md v2 §2/§3 — the v2 fix for the v1 field-exposure bug:
// profiles/{uid} is owner-read-only (no "public subset" leak), and
// profilesPublic/{uid} is the only readable-by-anyone doc, with zero client
// writes to it ever.
describe("profiles / profilesPublic rules", () => {
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
      await setDoc(doc(db, "profiles/staffA"), {
        role: "staff",
        name: "Staff A",
        dbsStatus: "unverified",
        rating: { average: 0, count: 0 },
      });
      await setDoc(doc(db, "profiles/staffB"), {
        role: "staff",
        name: "Staff B",
        dbsStatus: "unverified",
        rating: { average: 0, count: 0 },
      });
      await setDoc(doc(db, "profilesPublic/staffA"), {
        role: "staff",
        name: "Staff A",
        rating: { average: 0, count: 0 },
        dbsBadge: "unverified",
      });
    });
  });

  it("owner can read their own private profile", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(getDoc(doc(asStaffA, "profiles/staffA")));
  });

  it("another signed-in user cannot read someone else's private profile", async () => {
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    await assertFails(getDoc(doc(asStaffB, "profiles/staffA")));
  });

  it("owner can update their own name", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(
      updateDoc(doc(asStaffA, "profiles/staffA"), { name: "Staff A Updated" })
    );
  });

  it("owner cannot change their own dbsStatus", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profiles/staffA"), { dbsStatus: "verified" })
    );
  });

  it("a staff user cannot write another user's dbsStatus", async () => {
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    await assertFails(
      updateDoc(doc(asStaffB, "profiles/staffA"), { dbsStatus: "verified" })
    );
  });

  it("any authenticated user can read profilesPublic", async () => {
    const asStaffB = testEnv.authenticatedContext("staffB").firestore();
    await assertSucceeds(getDoc(doc(asStaffB, "profilesPublic/staffA")));
  });

  it("no client, including the owner, can write profilesPublic", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profilesPublic/staffA"), { name: "Hacked" })
    );
  });
});
