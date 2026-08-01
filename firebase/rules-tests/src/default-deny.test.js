import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';

const projectId = 'demo-michizure';
const documentPath = 'bootstrap-probe/denied-document';

let testEnvironment;

beforeAll(async () => {
  const rules = readFileSync(
    new URL('../../../firestore.rules', import.meta.url),
    'utf8',
  );

  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
});

afterAll(async () => {
  await testEnvironment.cleanup();
});

const contexts = [
  {
    label: 'unauthenticated client',
    firestore: () => testEnvironment.unauthenticatedContext().firestore(),
  },
  {
    label: 'authenticated client',
    firestore: () =>
      testEnvironment
        .authenticatedContext('bootstrap-test-user', {
          email: 'bootstrap@example.test',
        })
        .firestore(),
  },
];

const deniedOperations = [
  {
    label: 'get',
    prepare: async () => seedDocument(),
    execute: (reference) => getDoc(reference),
  },
  {
    label: 'create',
    prepare: async () => {},
    execute: (reference) => setDoc(reference, { value: 'created' }),
  },
  {
    label: 'update',
    prepare: async () => seedDocument(),
    execute: (reference) => updateDoc(reference, { value: 'updated' }),
  },
  {
    label: 'delete',
    prepare: async () => seedDocument(),
    execute: (reference) => deleteDoc(reference),
  },
];

describe.each(contexts)('default deny: $label', ({ firestore }) => {
  test.each(deniedOperations)('rejects $label', async ({ prepare, execute }) => {
    await prepare();
    const reference = doc(firestore(), documentPath);

    await expect(assertFails(execute(reference))).resolves.toBeDefined();
  });
});

async function seedDocument() {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), documentPath), { value: 'seed' });
  });
}
