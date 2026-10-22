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

  it("owner cannot change their own role after creation", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profiles/staffA"), { role: "nursery" })
    );
  });

  it("owner cannot change identityVerified", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profiles/staffA"), { identityVerified: true })
    );
  });

  it("owner cannot change ofstedVerified", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profiles/staffA"), { ofstedVerified: true })
    );
  });

  it("owner cannot change rightToWorkVerified", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profiles/staffA"), { rightToWorkVerified: true })
    );
  });

  it("owner cannot change suspended", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profiles/staffA"), { suspended: true })
    );
  });

  it("owner cannot change rating", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profiles/staffA"), { rating: { average: 5, count: 10 } })
    );
  });

  it("owner cannot change trainingCompletedModuleIds", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertFails(
      updateDoc(doc(asStaffA, "profiles/staffA"), { trainingCompletedModuleIds: ["module1"] })
    );
  });

  it("owner cannot change nurseryApprovalStatus or activationDate", async () => {
    const asNursery = testEnv.authenticatedContext("nurseryA").firestore();
    await assertFails(
      updateDoc(doc(asNursery, "profiles/nurseryA"), { nurseryApprovalStatus: "approved" })
    );
    await assertFails(
      updateDoc(doc(asNursery, "profiles/nurseryA"), { activationDate: new Date() })
    );
  });

  it("owner can update permitted fields", async () => {
    const asStaffA = testEnv.authenticatedContext("staffA").firestore();
    await assertSucceeds(
      updateDoc(doc(asStaffA, "profiles/staffA"), {
        bio: "Experienced practitioner",
        phone: "+441234567890",
        city: "London"
      })
    );
  });

  it("nursery owner can update Phase 5 registration fields", async () => {
    const asNursery = testEnv.authenticatedContext("nurseryA").firestore();
    await assertSucceeds(
      updateDoc(doc(asNursery, "profiles/nurseryA"), {
        companyNumber: "12345678",
        billingAddress: "123 Business Way",
        billingEmail: "accounts@nursery.co.uk",
        preferredPaymentMethod: "direct_debit",
        locationCount: 2,
        staffingRequirements: "Requires Level 3 practitioners for toddler room"
      })
    );
  });

  it("user can create profile with legal initial fields", async () => {
    const asNew = testEnv.authenticatedContext("newbie").firestore();
    await assertSucceeds(
      setDoc(doc(asNew, "profiles/newbie"), {
        role: "",
        name: "New Practitioner",
        dbsStatus: "unverified",
        rating: { average: 0, count: 0 },
        createdAt: new Date(),
      })
    );
  });

  it("user cannot create profile with verified dbsStatus", async () => {
    const asNew = testEnv.authenticatedContext("hacker1").firestore();
    await assertFails(
      setDoc(doc(asNew, "profiles/hacker1"), {
        role: "staff",
        name: "Hacker One",
        dbsStatus: "verified",
        rating: { average: 0, count: 0 },
        createdAt: new Date(),
      })
    );
  });

  it("user cannot create profile with suspended: true", async () => {
    const asNew = testEnv.authenticatedContext("hacker2").firestore();
    await assertFails(
      setDoc(doc(asNew, "profiles/hacker2"), {
        role: "staff",
        name: "Hacker Two",
        dbsStatus: "unverified",
        rating: { average: 0, count: 0 },
        createdAt: new Date(),
        suspended: true,
      })
    );
  });

  it("user cannot create profile with trust fields present", async () => {
    const asNew = testEnv.authenticatedContext("hacker3").firestore();
    await assertFails(
      setDoc(doc(asNew, "profiles/hacker3"), {
        role: "staff",
        name: "Hacker Three",
        dbsStatus: "unverified",
        rating: { average: 0, count: 0 },
        createdAt: new Date(),
        identityVerified: true,
      })
    );
  });
});
