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
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';

const projectId = 'demo-michizure';
const groupOne = 'group-one';
const groupTwo = 'group-two';
const alice = 'alice';
const bob = 'bob';
const carol = 'carol';
const detachedFailedUser = 'detached';
const fixed = Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z'));

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
  await seed();
});
afterAll(async () => testEnvironment.cleanup());

const firestoreAs = (uid) =>
  testEnvironment.authenticatedContext(uid).firestore();
const unauthenticated = () =>
  testEnvironment.unauthenticatedContext().firestore();

const member = (uid) => ({
  userId: uid,
  displayNameSnapshot: uid === alice ? '野々村 奏' : uid,
  role: uid === alice ? 'owner' : 'member',
  inviteTokenHash: uid === alice ? null : 'a'.repeat(64),
  joinedAt: fixed,
  updatedAt: fixed,
  schemaVersion: 1,
});

const debt = ({
  id,
  groupId = groupOne,
  failedUserId = alice,
  status = 'active',
  lockExpiresAt = Timestamp.fromMillis(Date.now() + 60_000),
  closedAt = null,
}) => ({
  groupId,
  failedUserId,
  failedTaskSessionId: id,
  memberCountAtFailure: 2,
  repsPerMember: 10,
  totalReps: 20,
  completedReps: status === 'completed' ? 20 : 0,
  status,
  createdAt: fixed,
  lockExpiresAt,
  closedAt,
  lastContributionAt: null,
  lastContributionEventId: null,
  schemaVersion: 1,
});

async function seed() {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, 'groups', groupOne), {
      name: '同じグループ',
      ownerUid: alice,
      memberCount: 2,
      createdAt: fixed,
      updatedAt: fixed,
      schemaVersion: 1,
    });
    await setDoc(doc(firestore, 'groups', groupTwo), {
      name: '別グループ',
      ownerUid: carol,
      memberCount: 1,
      createdAt: fixed,
      updatedAt: fixed,
      schemaVersion: 1,
    });
    await setDoc(
      doc(firestore, 'groups', groupOne, 'members', alice),
      member(alice),
    );
    await setDoc(
      doc(firestore, 'groups', groupOne, 'members', bob),
      member(bob),
    );
    await setDoc(
      doc(firestore, 'groups', groupTwo, 'members', carol),
      member(carol),
    );
    await setDoc(
      doc(firestore, 'debts', 'active-one'),
      debt({ id: 'active-one' }),
    );
    await setDoc(
      doc(firestore, 'debts', 'active-two'),
      debt({
        id: 'active-two',
        failedUserId: bob,
        lockExpiresAt: Timestamp.fromMillis(Date.now() + 120_000),
      }),
    );
    await setDoc(
      doc(firestore, 'debts', 'other-group'),
      debt({
        id: 'other-group',
        groupId: groupTwo,
        failedUserId: carol,
      }),
    );
    await setDoc(
      doc(firestore, 'debts', 'detached-debt'),
      debt({
        id: 'detached-debt',
        failedUserId: detachedFailedUser,
      }),
    );
    await setDoc(
      doc(firestore, 'debts', 'past-debt'),
      debt({
        id: 'past-debt',
        lockExpiresAt: Timestamp.fromMillis(Date.now() - 60_000),
      }),
    );
    await setDoc(
      doc(firestore, 'debts', 'completed-debt'),
      debt({
        id: 'completed-debt',
        status: 'completed',
        closedAt: fixed,
      }),
    );
    await setDoc(
      doc(
        firestore,
        'debts',
        'active-one',
        'contributions',
        bob,
      ),
      {
        userId: bob,
        totalReps: 3,
        lastEventId: 'event-3',
        lastContributedAt: fixed,
        schemaVersion: 1,
      },
    );
  });
}

const activeGroupQuery = (firestore, targetGroup = groupOne) =>
  query(
    collection(firestore, 'debts'),
    where('groupId', '==', targetGroup),
    where('status', '==', 'active'),
    orderBy('lockExpiresAt'),
    limit(20),
  );

describe('Debt read boundary and scoped queries', () => {
  test('unauthenticated direct get and query are independently denied', async () => {
    const firestore = unauthenticated();
    await assertFails(getDoc(doc(firestore, 'debts', 'active-one')));
    await assertFails(getDocs(activeGroupQuery(firestore)));
  });

  test('same-group member can direct get and run the bounded group query', async () => {
    const firestore = firestoreAs(bob);
    await assertSucceeds(getDoc(doc(firestore, 'debts', 'active-one')));
    const snapshot = await assertSucceeds(
      getDocs(activeGroupQuery(firestore)),
    );
    expect(snapshot.docs.length).toBe(4);
  });

  test('other-group member and unaffiliated user cannot read group Debt', async () => {
    const otherGroup = firestoreAs(carol);
    const outsider = firestoreAs('outsider');
    await assertFails(getDoc(doc(otherGroup, 'debts', 'active-one')));
    await assertFails(getDocs(activeGroupQuery(otherGroup)));
    await assertFails(getDoc(doc(outsider, 'debts', 'active-one')));
    await assertFails(getDocs(activeGroupQuery(outsider)));
  });

  test('failed user can read only their own active obligation query', async () => {
    const firestore = firestoreAs(detachedFailedUser);
    await assertSucceeds(
      getDoc(doc(firestore, 'debts', 'detached-debt')),
    );
    await assertFails(getDoc(doc(firestore, 'debts', 'active-one')));
    await assertSucceeds(
      getDocs(
        query(
          collection(firestore, 'debts'),
          where('failedUserId', '==', detachedFailedUser),
          where('status', '==', 'active'),
          orderBy('lockExpiresAt'),
          limit(20),
        ),
      ),
    );
  });

  test('unscoped and cross-group-capable queries are denied', async () => {
    const firestore = firestoreAs(bob);
    await assertFails(
      getDocs(
        query(
          collection(firestore, 'debts'),
          where('status', '==', 'active'),
          orderBy('lockExpiresAt'),
          limit(20),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          collection(firestore, 'debts'),
          where('groupId', 'in', [groupOne, groupTwo]),
          where('status', '==', 'active'),
          orderBy('lockExpiresAt'),
          limit(20),
        ),
      ),
    );
  });

  test('member summary is readable only by same-group members', async () => {
    const path = ['debts', 'active-one', 'contributions', bob];
    await assertSucceeds(getDoc(doc(firestoreAs(alice), ...path)));
    await assertFails(getDoc(doc(firestoreAs(carol), ...path)));
  });
});

describe('Debt expiration and write boundary', () => {
  test('deadline before expiration is denied', async () => {
    await assertFails(
      updateDoc(doc(firestoreAs(bob), 'debts', 'active-one'), {
        status: 'expired',
        closedAt: serverTimestamp(),
      }),
    );
  });

  test('deadline after expiration allows only active to expired', async () => {
    await assertSucceeds(
      updateDoc(doc(firestoreAs(bob), 'debts', 'past-debt'), {
        status: 'expired',
        closedAt: serverTimestamp(),
      }),
    );
    const snapshot = await getDoc(
      doc(firestoreAs(bob), 'debts', 'past-debt'),
    );
    expect(snapshot.data().status).toBe('expired');
  });

  test('terminal update and delete remain denied', async () => {
    const firestore = firestoreAs(alice);
    await assertFails(
      updateDoc(doc(firestore, 'debts', 'completed-debt'), {
        status: 'expired',
        closedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      deleteDoc(doc(firestore, 'debts', 'completed-debt')),
    );
  });

  test('extra fields and contribution writes remain denied', async () => {
    const firestore = firestoreAs(bob);
    await assertFails(
      updateDoc(doc(firestore, 'debts', 'past-debt'), {
        status: 'expired',
        closedAt: serverTimestamp(),
        packageName: 'private.package',
      }),
    );
    await assertFails(
      updateDoc(
        doc(firestore, 'debts', 'active-one', 'contributions', bob),
        { totalReps: 4 },
      ),
    );
  });

  test('Phase 7 does not add standalone Debt create permission', async () => {
    await assertFails(
      setDoc(
        doc(firestoreAs(bob), 'debts', 'forged-debt'),
        debt({ id: 'forged-debt', failedUserId: bob }),
      ),
    );
  });
});
