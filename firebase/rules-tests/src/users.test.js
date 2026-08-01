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
const fixedTimestamp = Timestamp.fromDate(
  new Date('2026-01-01T00:00:00.000Z'),
);

beforeAll(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId: 'demo-michizure',
    firestore: {
      rules: readFileSync(
        new URL('../../../firestore.rules', import.meta.url),
        'utf8',
      ),
    },
  });
});

beforeEach(async () => testEnvironment.clearFirestore());
afterAll(async () => testEnvironment.cleanup());

const validUser = (overrides = {}) => ({
  displayName: 'Alice',
  photoUrl: null,
  groupId: null,
  activeTaskSessionId: null,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  schemaVersion: 1,
  ...overrides,
});

const validDevice = (overrides = {}) => ({
  token: 'fcm-token',
  platform: 'android',
  updatedAt: serverTimestamp(),
  enabled: true,
  ...overrides,
});

const firestoreAs = (uid) =>
  testEnvironment.authenticatedContext(uid).firestore();

const unauthenticatedFirestore = () =>
  testEnvironment.unauthenticatedContext().firestore();

async function expectDenied(operation) {
  await expect(assertFails(operation)).resolves.toBeDefined();
}

async function seedUser(uid = aliceId) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users', uid),
      validUser({
        createdAt: fixedTimestamp,
        updatedAt: fixedTimestamp,
      }),
    );
  });
}

describe('users rules allow paths', () => {
  test('allows Unicode display names', async () => {
    const displayNames = [
      '野々村 奏',
      '奏',
      'かなで',
      'カナデ',
      'Kanade',
      'Kanade 野々村',
      'user123',
      '奏'.repeat(40),
    ];

    for (const [index, displayName] of displayNames.entries()) {
      const userId = `unicode-user-${index}`;
      await assertSucceeds(
        setDoc(
          doc(firestoreAs(userId), 'users', userId),
          validUser({ displayName }),
        ),
      );
    }
  });

  test('allows an authenticated user to create and get their profile', async () => {
    const alice = firestoreAs(aliceId);
    await assertSucceeds(
      setDoc(doc(alice, 'users', aliceId), validUser()),
    );
    await assertSucceeds(getDoc(doc(alice, 'users', aliceId)));
  });

  test('allows a profile-only display name update', async () => {
    await seedUser();
    await assertSucceeds(
      updateDoc(doc(firestoreAs(aliceId), 'users', aliceId), {
        displayName: 'Renamed',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test('allows a user to manage their own device registrations', async () => {
    const device = doc(
      firestoreAs(aliceId),
      'users',
      aliceId,
      'devices',
      '0123456789abcdef',
    );
    await assertSucceeds(setDoc(device, validDevice()));
    await assertSucceeds(getDoc(device));
    await assertSucceeds(
      updateDoc(device, {token: 'refreshed-token', updatedAt: serverTimestamp()}),
    );
    await assertSucceeds(deleteDoc(device));
  });
});

describe('users rules deny paths', () => {
  test('denies unauthenticated get', async () => {
    await seedUser();
    await expectDenied(
      getDoc(doc(unauthenticatedFirestore(), 'users', aliceId)),
    );
  });

  test('denies unauthenticated create', async () => {
    await expectDenied(
      setDoc(doc(unauthenticatedFirestore(), 'users', aliceId), validUser()),
    );
  });

  test('denies another UID get', async () => {
    await seedUser();
    await expectDenied(
      getDoc(doc(firestoreAs(bobId), 'users', aliceId)),
    );
  });

  test('denies another UID update', async () => {
    await seedUser();
    await expectDenied(
      updateDoc(doc(firestoreAs(bobId), 'users', aliceId), {
        displayName: 'Intruder',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test('denies access to another user device registration', async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(
          context.firestore(),
          'users',
          aliceId,
          'devices',
          '0123456789abcdef',
        ),
        validDevice({updatedAt: fixedTimestamp}),
      );
    });
    const device = doc(
      firestoreAs(bobId),
      'users',
      aliceId,
      'devices',
      '0123456789abcdef',
    );
    await expectDenied(getDoc(device));
    await expectDenied(setDoc(device, validDevice()));
    await expectDenied(deleteDoc(device));
  });

  test('denies malformed device registrations', async () => {
    const device = doc(
      firestoreAs(aliceId),
      'users',
      aliceId,
      'devices',
      '0123456789abcdef',
    );
    await expectDenied(setDoc(device, validDevice({platform: 'ios'})));
    await expectDenied(setDoc(device, validDevice({unexpected: true})));
  });

  test('denies UID spoofing on create', async () => {
    await expectDenied(
      setDoc(doc(firestoreAs(aliceId), 'users', bobId), validUser()),
    );
  });

  test('denies a missing required field', async () => {
    const user = validUser();
    delete user.photoUrl;
    await expectDenied(
      setDoc(doc(firestoreAs(aliceId), 'users', aliceId), user),
    );
  });

  test('denies an extra field on create for the same UID', async () => {
    await expectDenied(
      setDoc(
        doc(firestoreAs(aliceId), 'users', aliceId),
        validUser({ unexpected: true }),
      ),
    );
  });

  test('denies a client-provided create timestamp', async () => {
    await expectDenied(
      setDoc(
        doc(firestoreAs(aliceId), 'users', aliceId),
        validUser({ createdAt: fixedTimestamp }),
      ),
    );
  });

  test('denies an extra field on update', async () => {
    await seedUser();
    await expectDenied(
      updateDoc(doc(firestoreAs(aliceId), 'users', aliceId), {
        unexpected: true,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test('denies activeTaskSessionId changes', async () => {
    await seedUser();
    await expectDenied(
      updateDoc(doc(firestoreAs(aliceId), 'users', aliceId), {
        activeTaskSessionId: 'task-id',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test('denies createdAt changes', async () => {
    await seedUser();
    await expectDenied(
      updateDoc(doc(firestoreAs(aliceId), 'users', aliceId), {
        createdAt: Timestamp.fromDate(
          new Date('2026-01-02T00:00:00.000Z'),
        ),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test('denies schemaVersion changes', async () => {
    await seedUser();
    await expectDenied(
      updateDoc(doc(firestoreAs(aliceId), 'users', aliceId), {
        schemaVersion: 2,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test('denies other protected field changes', async () => {
    await seedUser();
    await expectDenied(
      updateDoc(doc(firestoreAs(aliceId), 'users', aliceId), {
        groupId: 'group-id',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test('denies delete', async () => {
    await seedUser();
    await expectDenied(
      deleteDoc(doc(firestoreAs(aliceId), 'users', aliceId)),
    );
  });

  test('denies list', async () => {
    await seedUser();
    await expectDenied(getDocs(collection(firestoreAs(aliceId), 'users')));
  });

  test('denies blank, control-character, and too-long display names', async () => {
    const invalidDisplayNames = [
      '',
      '  ',
      '\n',
      'Kanade\n奏',
      '奏'.repeat(41),
    ];

    for (const [index, displayName] of invalidDisplayNames.entries()) {
      const userId = `invalid-name-${index}`;
      await expectDenied(
        setDoc(
          doc(firestoreAs(userId), 'users', userId),
          validUser({ displayName }),
        ),
      );
    }
  });

  test('denies non-canonical surrounding whitespace', async () => {
    const invalidDisplayNames = [
      ' Alice',
      'Alice ',
      '  Alice  ',
      '\u00a0Alice',
      'Alice\u3000',
    ];

    for (const [index, displayName] of invalidDisplayNames.entries()) {
      const userId = `non-canonical-name-${index}`;
      await expectDenied(
        setDoc(
          doc(firestoreAs(userId), 'users', userId),
          validUser({ displayName }),
        ),
      );
    }
  });
});
