import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendRoot = path.resolve(__dirname, "..");

// Mirrors backend/firebase.json's fixed emulator ports (ARCHITECTURE.md v2 §7).
const FIRESTORE_PORT = 8180;
const STORAGE_PORT = 9199;

export async function newTestEnv() {
  return initializeTestEnvironment({
    projectId: "demo-bridgeflex-rules-test",
    firestore: {
      rules: readFileSync(path.join(backendRoot, "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: FIRESTORE_PORT,
    },
    storage: {
      rules: readFileSync(path.join(backendRoot, "storage.rules"), "utf8"),
      host: "127.0.0.1",
      port: STORAGE_PORT,
    },
  });
}

// seed writes documents with rules disabled — the equivalent of an
// Admin-SDK write from a Cloud Function, used to set up fixture state that a
// client could never legally write directly.
export async function seed(testEnv, fn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await fn(context.firestore());
  });
}
