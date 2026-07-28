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
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';

const projectId = 'demo-michizure';
const aliceId = 'alice';
const bobId = 'bob';
const groupId = 'group-one';
const fixedTimestamp = Timestamp.fromDate(
  new Date('2026-01-01T00:00:00.000Z'),
);

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

beforeEach(async () => testEnvironment.clearFirestore());
afterAll(async () => testEnvironment.cleanup());

const firestoreAs = (uid) =>
  testEnvironment.authenticatedContext(uid).firestore();
const unauthenticatedFirestore = () =>
  testEnvironment.unauthenticatedContext().firestore();

const userData = ({
  uid = aliceId,
  activeTaskSessionId = null,
  membership = groupId,
} = {}) => ({
  displayName: uid,
  photoUrl: null,
  groupId: membership,
  activeTaskSessionId,
  createdAt: fixedTimestamp,
  updatedAt: fixedTimestamp,
  schemaVersion: 1,
});

const groupData = ({ memberCount = 1 } = {}) => ({
  name: '集中チーム',
  ownerUid: aliceId,
  memberCount,
  createdAt: fixedTimestamp,
  updatedAt: fixedTimestamp,
  schemaVersion: 1,
});

const memberData = ({ uid, role = 'member' }) => ({
  userId: uid,
  displayNameSnapshot: uid,
  role,
  inviteTokenHash: role === 'owner' ? null : 'a'.repeat(64),
  joinedAt: fixedTimestamp,
  updatedAt: fixedTimestamp,
  schemaVersion: 1,
});

const taskData = ({
  ownerUid = aliceId,
  targetGroupId = groupId,
  startedAt = Timestamp.fromDate(new Date()),
  durationSec = 1800,
  status = 'running',
  endedAt = null,
  failureReason = null,
  failureEventId = null,
  memberCountAtFailure = null,
  debtId = null,
  content = '勉強する',
  serverRecordedAt = serverTimestamp(),
  extra = {},
} = {}) => ({
  ownerUid,
  groupId: targetGroupId,
  content,
  durationSec,
  startedAt,
  serverRecordedAt,
  expectedEndAt: Timestamp.fromMillis(
    startedAt.toMillis() + durationSec * 1000,
  ),
  status,
  endedAt,
  failureReason,
  failureEventId,
  groupMemberCountAtFailure: memberCountAtFailure,
  debtId,
  lockDurationSec: 1800,
  guardConfigVersion: 1,
  schemaVersion: 1,
  ...extra,
});

const debtData = ({
  taskId,
  memberCount,
  endedAt,
  totalReps = memberCount * 10,
  extra = {},
}) => ({
  groupId,
  failedUserId: aliceId,
  failedTaskSessionId: taskId,
  memberCountAtFailure: memberCount,
  repsPerMember: 10,
  totalReps,
  completedReps: 0,
  status: 'active',
  createdAt: serverTimestamp(),
  lockExpiresAt: Timestamp.fromMillis(endedAt.toMillis() + 1800 * 1000),
  closedAt: null,
  lastContributionAt: null,
  lastContributionEventId: null,
  schemaVersion: 1,
  ...extra,
});

async function seedGroup(memberCount = 1) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, 'groups', groupId), groupData({ memberCount }));
    for (let index = 0; index < memberCount; index += 1) {
      const uid = index === 0 ? aliceId : `member-${index}`;
      await setDoc(
        doc(firestore, 'groups', groupId, 'members', uid),
        memberData({ uid, role: index === 0 ? 'owner' : 'member' }),
      );
      await setDoc(
        doc(firestore, 'users', uid),
        userData({ uid }),
      );
    }
  });
}

async function seedRunningTask({
  taskId = 'task-running',
  expectedInPast = false,
} = {}) {
  const startedAt = Timestamp.fromDate(
    expectedInPast
      ? new Date(Date.now() - 2 * 60 * 1000)
      : new Date(),
  );
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(
      doc(firestore, 'taskSessions', taskId),
      taskData({
        startedAt,
        durationSec: 60,
        serverRecordedAt: fixedTimestamp,
      }),
    );
    await updateDoc(doc(firestore, 'users', aliceId), {
      activeTaskSessionId: taskId,
    });
  });
  return taskId;
}

function startTaskAtomic(
  firestore,
  taskId,
  { taskOverrides = {}, includePointer = true } = {},
) {
  const batch = writeBatch(firestore);
  batch.set(
    doc(firestore, 'taskSessions', taskId),
    taskData(taskOverrides),
  );
  if (includePointer) {
    batch.update(doc(firestore, 'users', aliceId), {
      activeTaskSessionId: taskId,
      updatedAt: serverTimestamp(),
    });
  }
  return batch.commit();
}

function succeedTaskAtomic(firestore, taskId) {
  const batch = writeBatch(firestore);
  batch.update(doc(firestore, 'taskSessions', taskId), {
    status: 'succeeded',
    endedAt: serverTimestamp(),
  });
  batch.update(doc(firestore, 'users', aliceId), {
    activeTaskSessionId: null,
    updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

function failTaskAtomic(
  firestore,
  taskId,
  memberCount,
  { includeDebt = true, totalReps = memberCount * 10 } = {},
) {
  const endedAt = Timestamp.fromDate(new Date());
  const batch = writeBatch(firestore);
  batch.update(doc(firestore, 'taskSessions', taskId), {
    status: 'failed',
    endedAt,
    failureReason: 'user_aborted',
    failureEventId: `manual_${taskId}_event`,
    groupMemberCountAtFailure: memberCount,
    debtId: taskId,
  });
  batch.update(doc(firestore, 'users', aliceId), {
    activeTaskSessionId: null,
    updatedAt: serverTimestamp(),
  });
  if (includeDebt) {
    batch.set(
      doc(firestore, 'debts', taskId),
      debtData({ taskId, memberCount, endedAt, totalReps }),
    );
  }
  return batch.commit();
}

async function expectDenied(operation) {
  await expect(assertFails(operation)).resolves.toBeDefined();
}

describe('Task start atomic invariants', () => {
  test('creates a running Task with its user pointer atomically', async () => {
    await seedGroup();
    const alice = firestoreAs(aliceId);

    await assertSucceeds(startTaskAtomic(alice, 'task-one'));
    const task = await getDoc(doc(alice, 'taskSessions', 'task-one'));
    expect(task.data().status).toBe('running');
  });

  test('denies a running Task without the active pointer', async () => {
    await seedGroup();
    await expectDenied(
      startTaskAtomic(firestoreAs(aliceId), 'task-no-pointer', {
        includePointer: false,
      }),
    );
  });

  test('denies unauthenticated start independently', async () => {
    await seedGroup();
    await expectDenied(
      startTaskAtomic(unauthenticatedFirestore(), 'task-unauthenticated'),
    );
  });

  test('denies malformed deadline, duration, content, and extra fields', async () => {
    await seedGroup();
    const alice = firestoreAs(aliceId);
    const now = Timestamp.fromDate(new Date());

    await expectDenied(
      startTaskAtomic(alice, 'task-bad-deadline', {
        taskOverrides: {
          startedAt: now,
          durationSec: 60,
          extra: {
            expectedEndAt: Timestamp.fromMillis(now.toMillis() + 61_000),
          },
        },
      }),
    );
    await expectDenied(
      startTaskAtomic(alice, 'task-bad-duration', {
        taskOverrides: { durationSec: 59 },
      }),
    );
    await expectDenied(
      startTaskAtomic(alice, 'task-bad-content', {
        taskOverrides: { content: '  ' },
      }),
    );
    await expectDenied(
      startTaskAtomic(alice, 'task-extra-field', {
        taskOverrides: { extra: { packageName: 'private.app' } },
      }),
    );
  });

  test('concurrent starts leave at most one running Task', async () => {
    await seedGroup();
    const alice = firestoreAs(aliceId);

    const results = await Promise.allSettled([
      startTaskAtomic(alice, 'task-concurrent-a'),
      startTaskAtomic(alice, 'task-concurrent-b'),
    ]);
    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const snapshot = await getDocs(
        collection(context.firestore(), 'taskSessions'),
      );
      expect(snapshot.docs).toHaveLength(1);
    });
  });
});

describe('Task authorization and immutability', () => {
  beforeEach(async () => {
    await seedGroup();
    await seedRunningTask();
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), 'users', bobId),
        userData({ uid: bobId, membership: null }),
      );
    });
  });

  test('allows only the owner to get a Task', async () => {
    await assertSucceeds(
      getDoc(doc(firestoreAs(aliceId), 'taskSessions', 'task-running')),
    );
    await expectDenied(
      getDoc(doc(firestoreAs(bobId), 'taskSessions', 'task-running')),
    );
    await expectDenied(
      getDoc(
        doc(unauthenticatedFirestore(), 'taskSessions', 'task-running'),
      ),
    );
  });

  test('allows an owner-scoped query and denies other or unscoped queries', async () => {
    await assertSucceeds(
      getDocs(
        query(
          collection(firestoreAs(aliceId), 'taskSessions'),
          where('ownerUid', '==', aliceId),
        ),
      ),
    );
    await expectDenied(
      getDocs(
        query(
          collection(firestoreAs(bobId), 'taskSessions'),
          where('ownerUid', '==', aliceId),
        ),
      ),
    );
    await expectDenied(
      getDocs(collection(firestoreAs(aliceId), 'taskSessions')),
    );
  });

  test('denies protected fields, status forgery, extra fields, and delete', async () => {
    const aliceTask = doc(
      firestoreAs(aliceId),
      'taskSessions',
      'task-running',
    );
    await expectDenied(updateDoc(aliceTask, { durationSec: 120 }));
    await expectDenied(
      updateDoc(aliceTask, {
        status: 'failed',
        endedAt: serverTimestamp(),
      }),
    );
    await expectDenied(updateDoc(aliceTask, { unexpected: true }));
    await expectDenied(deleteDoc(aliceTask));
  });

  test('denies another user update independently', async () => {
    await expectDenied(
      updateDoc(
        doc(firestoreAs(bobId), 'taskSessions', 'task-running'),
        { content: '侵入' },
      ),
    );
  });
});

describe('Task terminal transitions and minimal Debt', () => {
  test('Task owner may check its matching missing Debt ID only', async () => {
    await seedGroup();
    const taskId = await seedRunningTask();
    await assertSucceeds(
      getDoc(doc(firestoreAs(aliceId), 'debts', taskId)),
    );
    await expectDenied(
      getDoc(doc(firestoreAs(aliceId), 'debts', 'unrelated-missing-id')),
    );
    await expectDenied(
      getDoc(
        doc(unauthenticatedFirestore(), 'debts', taskId),
      ),
    );
  });

  test('denies success before expectedEndAt', async () => {
    await seedGroup();
    const taskId = await seedRunningTask();

    await expectDenied(succeedTaskAtomic(firestoreAs(aliceId), taskId));
  });

  test('allows overdue success and clears the active pointer', async () => {
    await seedGroup();
    const taskId = await seedRunningTask({ expectedInPast: true });

    await assertSucceeds(succeedTaskAtomic(firestoreAs(aliceId), taskId));
    const task = await getDoc(
      doc(firestoreAs(aliceId), 'taskSessions', taskId),
    );
    expect(task.data().status).toBe('succeeded');
  });

  test.each([1, 5, 40])(
    'manual failure at %i members creates the same-ID Debt',
    async (memberCount) => {
      await seedGroup(memberCount);
      const taskId = await seedRunningTask({
        taskId: `failed-${memberCount}`,
      });

      await assertSucceeds(
        failTaskAtomic(
          firestoreAs(aliceId),
          taskId,
          memberCount,
        ),
      );
      const debt = await getDoc(
        doc(firestoreAs(aliceId), 'debts', taskId),
      );
      expect(debt.data().totalReps).toBe(memberCount * 10);
    },
  );

  test('denies failure without its Debt', async () => {
    await seedGroup(5);
    const taskId = await seedRunningTask();

    await expectDenied(
      failTaskAtomic(firestoreAs(aliceId), taskId, 5, {
        includeDebt: false,
      }),
    );
  });

  test('denies a Debt amount different from memberCount times 10', async () => {
    await seedGroup(5);
    const taskId = await seedRunningTask();

    await expectDenied(
      failTaskAtomic(firestoreAs(aliceId), taskId, 5, {
        totalReps: 49,
      }),
    );
  });

  test('terminal Task and initial Debt cannot be changed or deleted', async () => {
    await seedGroup();
    const taskId = await seedRunningTask({ expectedInPast: true });
    const alice = firestoreAs(aliceId);
    await assertSucceeds(succeedTaskAtomic(alice, taskId));

    await expectDenied(
      updateDoc(doc(alice, 'taskSessions', taskId), {
        status: 'failed',
      }),
    );
    await expectDenied(deleteDoc(doc(alice, 'taskSessions', taskId)));

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const endedAt = Timestamp.fromDate(new Date());
      await setDoc(
        doc(context.firestore(), 'debts', 'seed-debt'),
        debtData({ taskId: 'seed-debt', memberCount: 1, endedAt }),
      );
    });
    await expectDenied(
      updateDoc(doc(alice, 'debts', 'seed-debt'), {
        completedReps: 1,
      }),
    );
    await expectDenied(deleteDoc(doc(alice, 'debts', 'seed-debt')));
  });
});
