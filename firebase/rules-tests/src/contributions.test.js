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
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';

const projectId = 'demo-michizure';
const groupId = 'group-contributions';
const otherGroupId = 'group-other';
const fixed = Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z'));
const sessionId = '0123456789abcdef0123456789abcdef';
const alice = 'alice';
const bob = 'bob';
const carol = 'carol';

let testEnvironment;

beforeAll(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(
        new URL('../../../firestore.rules', import.meta.url),
        'utf8',
      ),
    },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await seedBase();
});

afterAll(async () => testEnvironment.cleanup());

const firestoreAs = (uid) =>
  testEnvironment.authenticatedContext(uid).firestore();
const unauthenticated = () =>
  testEnvironment.unauthenticatedContext().firestore();

const eventIdFor = (uid, sequence) => `${uid}_${sessionId}_${sequence}`;

const member = (uid, role = 'member') => ({
  userId: uid,
  displayNameSnapshot: uid === alice ? '野々村 奏' : uid,
  role,
  inviteTokenHash: role === 'owner' ? null : 'a'.repeat(64),
  joinedAt: fixed,
  updatedAt: fixed,
  schemaVersion: 1,
});

const debt = ({
  id,
  completedReps = 0,
  memberCountAtFailure = 5,
  status = 'active',
  lockExpiresAt = Timestamp.fromMillis(Date.now() + 10 * 60_000),
  closedAt = null,
  targetGroupId = groupId,
}) => ({
  groupId: targetGroupId,
  failedUserId: alice,
  failedTaskSessionId: id,
  memberCountAtFailure,
  repsPerMember: 10,
  totalReps: memberCountAtFailure * 10,
  completedReps,
  status,
  createdAt: fixed,
  lockExpiresAt,
  closedAt,
  lastContributionAt: null,
  lastContributionEventId: null,
  schemaVersion: 1,
});

async function seedBase() {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, 'groups', groupId), {
      name: '返済グループ',
      ownerUid: alice,
      memberCount: 3,
      createdAt: fixed,
      updatedAt: fixed,
      schemaVersion: 1,
    });
    await setDoc(doc(firestore, 'groups', otherGroupId), {
      name: '別グループ',
      ownerUid: carol,
      memberCount: 1,
      createdAt: fixed,
      updatedAt: fixed,
      schemaVersion: 1,
    });
    await setDoc(
      doc(firestore, 'groups', groupId, 'members', alice),
      member(alice, 'owner'),
    );
    await setDoc(
      doc(firestore, 'groups', groupId, 'members', bob),
      member(bob),
    );
    await setDoc(
      doc(firestore, 'groups', otherGroupId, 'members', carol),
      member(carol, 'owner'),
    );
    await setDoc(
      doc(firestore, 'debts', 'active-50'),
      debt({ id: 'active-50' }),
    );
    await setDoc(
      doc(firestore, 'debts', 'at-49'),
      debt({ id: 'at-49', completedReps: 49 }),
    );
    await setDoc(
      doc(firestore, 'debts', 'at-9'),
      debt({
        id: 'at-9',
        completedReps: 9,
        memberCountAtFailure: 1,
      }),
    );
    await setDoc(
      doc(firestore, 'debts', 'terminal'),
      debt({
        id: 'terminal',
        completedReps: 50,
        status: 'completed',
        closedAt: fixed,
      }),
    );
    await setDoc(
      doc(firestore, 'debts', 'past-deadline'),
      debt({
        id: 'past-deadline',
        lockExpiresAt: Timestamp.fromMillis(Date.now() - 60_000),
      }),
    );
  });
}

async function addMembers(uids) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    for (const uid of uids) {
      await setDoc(
        doc(firestore, 'groups', groupId, 'members', uid),
        member(uid),
      );
    }
  });
}

async function submitRep(
  firestore,
  options,
) {
  const maximumAttempts = options.retryOnContention ? 60 : 1;
  for (let attempt = 0; attempt < maximumAttempts; attempt += 1) {
    try {
      return await submitRepOnce(firestore, options);
    } catch (error) {
      if (error.code !== 'permission-denied') {
        throw error;
      }
      try {
        const snapshot = await getDoc(
          doc(firestore, 'debts', options.debtId ?? 'active-50'),
        );
        const current = snapshot.data();
        if (
          current?.status !== 'active' ||
          current.completedReps >= current.totalReps
        ) {
          return 'rejected';
        }
      } catch {
        throw error;
      }
      if (!options.retryOnContention) {
        throw error;
      }
    }
  }
  throw new Error('Contribution contention retry budget exhausted');
}

async function submitRepOnce(
  firestore,
  {
    uid,
    debtId = 'active-50',
    sequence = 1,
    eventId = eventIdFor(uid, sequence),
    eventOverrides = {},
    summaryOverrides = {},
    debtOverrides = {},
    omit = null,
  },
) {
  return runTransaction(firestore, async (transaction) => {
    const debtReference = doc(firestore, 'debts', debtId);
    const eventReference = doc(
      firestore,
      'debts',
      debtId,
      'contributionEvents',
      eventId,
    );
    const summaryReference = doc(
      firestore,
      'debts',
      debtId,
      'contributions',
      uid,
    );
    const debtSnapshot = await transaction.get(debtReference);
    const eventSnapshot = await transaction.get(eventReference);
    const summarySnapshot = await transaction.get(summaryReference);
    if (eventSnapshot.exists()) {
      return 'duplicate';
    }
    const current = debtSnapshot.data();
    if (
      !debtSnapshot.exists() ||
      current.status !== 'active' ||
      current.completedReps >= current.totalReps
    ) {
      return 'rejected';
    }
    const nextCompleted = current.completedReps + 1;
    const completes = nextCompleted === current.totalReps;
    if (omit !== 'event') {
      transaction.set(eventReference, {
        userId: uid,
        squatSessionId: sessionId,
        sequence,
        acceptedReps: 1,
        detectorType: 'mlkit',
        detectorVersion: 'fsm-v1',
        clientObservedAt: Timestamp.now(),
        createdAt: serverTimestamp(),
        schemaVersion: 1,
        ...eventOverrides,
      });
    }
    if (omit !== 'summary') {
      transaction.set(summaryReference, {
        userId: uid,
        totalReps: (summarySnapshot.data()?.totalReps ?? 0) + 1,
        lastEventId: eventId,
        lastContributedAt: serverTimestamp(),
        schemaVersion: 1,
        ...summaryOverrides,
      });
    }
    if (omit !== 'debt') {
      transaction.update(debtReference, {
        completedReps: nextCompleted,
        status: completes ? 'completed' : 'active',
        closedAt: completes ? serverTimestamp() : null,
        lastContributionAt: serverTimestamp(),
        lastContributionEventId: eventId,
        ...debtOverrides,
      });
    }
    return 'accepted';
  });
}

describe('Contribution atomic workflow', () => {
  test('same-group member creates event, summary and Debt +1 atomically', async () => {
    const firestore = firestoreAs(bob);
    await expect(
      assertSucceeds(submitRep(firestore, { uid: bob })),
    ).resolves.toBe('accepted');

    const debtSnapshot = await getDoc(
      doc(firestore, 'debts', 'active-50'),
    );
    const summarySnapshot = await getDoc(
      doc(firestore, 'debts', 'active-50', 'contributions', bob),
    );
    const eventSnapshot = await getDoc(
      doc(
        firestore,
        'debts',
        'active-50',
        'contributionEvents',
        eventIdFor(bob, 1),
      ),
    );
    expect(debtSnapshot.data().completedReps).toBe(1);
    expect(debtSnapshot.data().lastContributionEventId).toBe(
      eventIdFor(bob, 1),
    );
    expect(summarySnapshot.data().totalReps).toBe(1);
    expect(eventSnapshot.data().acceptedReps).toBe(1);
  });

  test('same event retry is a no-op and immutable event cannot be replaced', async () => {
    const firestore = firestoreAs(bob);
    await assertSucceeds(submitRep(firestore, { uid: bob }));
    await expect(
      assertSucceeds(submitRep(firestore, { uid: bob })),
    ).resolves.toBe('duplicate');
    expect(
      (await getDoc(doc(firestore, 'debts', 'active-50'))).data()
        .completedReps,
    ).toBe(1);
    await assertFails(
      updateDoc(
        doc(
          firestore,
          'debts',
          'active-50',
          'contributionEvents',
          eventIdFor(bob, 1),
        ),
        { acceptedReps: 2 },
      ),
    );
    await assertFails(
      deleteDoc(
        doc(
          firestore,
          'debts',
          'active-50',
          'contributionEvents',
          eventIdFor(bob, 1),
        ),
      ),
    );
  });

  test.each(['event', 'summary', 'debt'])(
    'missing %s write is independently denied',
    async (omit) => {
      await assertFails(
        submitRep(firestoreAs(bob), {
          uid: bob,
          eventId: eventIdFor(bob, 10 + omit.length),
          sequence: 10 + omit.length,
          omit,
        }),
      );
    },
  );

  test('last rep completes Debt in the same transaction', async () => {
    const firestore = firestoreAs(bob);
    await assertSucceeds(
      submitRep(firestore, { uid: bob, debtId: 'at-49' }),
    );
    const snapshot = await getDoc(doc(firestore, 'debts', 'at-49'));
    expect(snapshot.data().completedReps).toBe(50);
    expect(snapshot.data().status).toBe('completed');
    expect(snapshot.data().closedAt).toBeInstanceOf(Timestamp);
  });
});

describe('Contribution authorization and validation', () => {
  test('unauthenticated, outsider and other-group users are denied independently', async () => {
    await assertFails(
      submitRep(unauthenticated(), { uid: 'anonymous' }),
    );
    await assertFails(
      submitRep(firestoreAs('outsider'), { uid: 'outsider' }),
    );
    await assertFails(submitRep(firestoreAs(carol), { uid: carol }));
  });

  test('UID spoofing and invalid event ID are denied independently', async () => {
    await assertFails(
      submitRep(firestoreAs(bob), {
        uid: alice,
        eventId: eventIdFor(alice, 2),
        sequence: 2,
      }),
    );
    await assertFails(
      submitRep(firestoreAs(bob), {
        uid: bob,
        eventId: 'forged-event',
        sequence: 2,
      }),
    );
  });

  test('zero, negative and oversized deltas are denied', async () => {
    for (const acceptedReps of [0, -1, 2, 999999]) {
      await assertFails(
        submitRep(firestoreAs(bob), {
          uid: bob,
          sequence: 100 + acceptedReps,
          eventId: eventIdFor(bob, 100 + acceptedReps),
          eventOverrides: { acceptedReps },
        }),
      );
    }
  });

  test('terminal and deadline Debt reject Contribution', async () => {
    await expect(
      assertSucceeds(
        submitRep(firestoreAs(bob), {
          uid: bob,
          debtId: 'terminal',
        }),
      ),
    ).resolves.toBe('rejected');
    await assertFails(
      submitRep(firestoreAs(bob), {
        uid: bob,
        debtId: 'past-deadline',
      }),
    );
  });

  test('extra fields and timestamp forgery are denied independently', async () => {
    await assertFails(
      submitRep(firestoreAs(bob), {
        uid: bob,
        sequence: 20,
        eventId: eventIdFor(bob, 20),
        eventOverrides: { packageName: 'private.package' },
      }),
    );
    await assertFails(
      submitRep(firestoreAs(bob), {
        uid: bob,
        sequence: 21,
        eventId: eventIdFor(bob, 21),
        eventOverrides: { createdAt: fixed },
      }),
    );
  });

  test('summary and Debt direct tampering remain denied', async () => {
    const firestore = firestoreAs(bob);
    await assertFails(
      setDoc(
        doc(firestore, 'debts', 'active-50', 'contributions', bob),
        {
          userId: bob,
          totalReps: 100,
          lastEventId: eventIdFor(bob, 1),
          lastContributedAt: serverTimestamp(),
          schemaVersion: 1,
        },
      ),
    );
    await assertFails(
      updateDoc(doc(firestore, 'debts', 'active-50'), {
        completedReps: 50,
        status: 'completed',
        closedAt: serverTimestamp(),
        lastContributionAt: serverTimestamp(),
        lastContributionEventId: eventIdFor(bob, 1),
      }),
    );
  });

  test('Contribution Event list query is denied', async () => {
    await assertFails(
      getDocs(
        collection(
          firestoreAs(bob),
          'debts',
          'active-50',
          'contributionEvents',
        ),
      ),
    );
  });
});

describe('Contribution concurrency and cap', () => {
  test('remaining 1 with 20 clients accepts exactly one event', async () => {
    const users = Array.from({ length: 20 }, (_, index) => `member${index}`);
    await addMembers(users);
    const results = await Promise.all(
      users.map((uid, index) =>
        submitRep(firestoreAs(uid), {
          uid,
          debtId: 'at-49',
          sequence: index + 1,
          retryOnContention: true,
        }),
      ),
    );
    expect(results.filter((result) => result === 'accepted')).toHaveLength(1);
    const finalDebt = await adminGet('debts/at-49');
    expect(finalDebt.completedReps).toBe(50);
    expect(finalDebt.status).toBe('completed');
    expect(await adminEventCount('at-49')).toBe(1);
    expect(await adminSummaryTotal('at-49')).toBe(1);
  });

  test('remaining 1 with two clients never exceeds total', async () => {
    const results = await Promise.all([
      submitRep(firestoreAs(alice), {
        uid: alice,
        debtId: 'at-9',
        retryOnContention: true,
      }),
      submitRep(firestoreAs(bob), {
        uid: bob,
        debtId: 'at-9',
        retryOnContention: true,
      }),
    ]);
    expect(results.filter((result) => result === 'accepted')).toHaveLength(1);
    const finalDebt = await adminGet('debts/at-9');
    expect(finalDebt.completedReps).toBe(10);
    expect(finalDebt.status).toBe('completed');
    expect(await adminEventCount('at-9')).toBe(1);
  });

  test(
    'five members submitting 50 unique reps preserve aggregate and summaries',
    async () => {
      const users = ['member-a', 'member-b', 'member-c', 'member-d', 'member-e'];
      await addMembers(users);
      const requests = [];
      for (const uid of users) {
        for (let sequence = 1; sequence <= 10; sequence += 1) {
          requests.push(
            submitRep(firestoreAs(uid), {
              uid,
              sequence,
              retryOnContention: true,
            }),
          );
        }
      }
      const results = await Promise.all(requests);
      expect(results.every((result) => result === 'accepted')).toBe(true);
      const finalDebt = await adminGet('debts/active-50');
      expect(finalDebt.completedReps).toBe(50);
      expect(finalDebt.status).toBe('completed');
      expect(await adminEventCount('active-50')).toBe(50);
      expect(await adminSummaryTotal('active-50')).toBe(50);
    },
    30_000,
  );
});

async function adminGet(path) {
  let result;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDoc(doc(context.firestore(), path));
    result = snapshot.data();
  });
  return result;
}

async function adminEventCount(debtId) {
  let result = 0;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDocs(
      collection(
        context.firestore(),
        'debts',
        debtId,
        'contributionEvents',
      ),
    );
    result = snapshot.size;
  });
  return result;
}

async function adminSummaryTotal(debtId) {
  let result = 0;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDocs(
      collection(
        context.firestore(),
        'debts',
        debtId,
        'contributions',
      ),
    );
    result = snapshot.docs.reduce(
      (total, item) => total + item.data().totalReps,
      0,
    );
  });
  return result;
}
