import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';

let testEnvironment;
const aliceId = 'alice';
const bobId = 'bob';

beforeAll(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId: 'demo-michizure',
    firestore: {
      rules: readFileSync(new URL('../../../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

beforeEach(async () => testEnvironment.clearFirestore());
afterAll(async () => testEnvironment.cleanup());

const validUser = () => ({
  displayName: 'Alice',
  photoUrl: null,
  groupId: null,
  activeTaskSessionId: null,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  schemaVersion: 1,
});

const firestoreAs = (uid) => testEnvironment.authenticatedContext(uid).firestore();

async function seedUser(uid) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', uid), {
      ...validUser(),
      createdAt: Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z')),
      updatedAt: Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z')),
    });
  });
}

describe('users rules', () => {
  test('allows an authenticated user to create and get only their profile', async () => {
    const alice = firestoreAs(aliceId);
    await assertSucceeds(setDoc(doc(alice, 'users', aliceId), validUser()));
    await assertSucceeds(getDoc(doc(alice, 'users', aliceId)));
  });

  test('allows a profile-only display name update', async () => {
    await seedUser(aliceId);
    await assertSucceeds(updateDoc(doc(firestoreAs(aliceId), 'users', aliceId), {
      displayName: 'Renamed',
      updatedAt: serverTimestamp(),
    }));
  });

  test('denies unauthenticated and other-user access', async () => {
    await seedUser(aliceId);
    const unauthenticated = testEnvironment.unauthenticatedContext().firestore();
    await expect(assertFails(getDoc(doc(unauthenticated, 'users', aliceId)))).resolves.toBeDefined();
    await expect(assertFails(getDoc(doc(firestoreAs(bobId), 'users', aliceId)))).resolves.toBeDefined();
    await expect(assertFails(updateDoc(doc(firestoreAs(bobId), 'users', aliceId), {
      displayName: 'Intruder', updatedAt: serverTimestamp(),
    }))).resolves.toBeDefined();
  });

  test('denies list, delete, extra fields, and protected-field changes', async () => {
    await seedUser(aliceId);
    const alice = firestoreAs(aliceId);
    await expect(assertFails(getDocs(collection(alice, 'users')))).resolves.toBeDefined();
    await expect(assertFails(deleteDoc(doc(alice, 'users', aliceId)))).resolves.toBeDefined();
    await expect(assertFails(setDoc(doc(alice, 'users', 'extra'), {
      ...validUser(), unexpected: true,
    }))).resolves.toBeDefined();
    await expect(assertFails(updateDoc(doc(alice, 'users', aliceId), {
      groupId: 'group-id', updatedAt: serverTimestamp(),
    }))).resolves.toBeDefined();
  });
});
