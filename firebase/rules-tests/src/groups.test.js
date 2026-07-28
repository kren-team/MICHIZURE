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
  increment,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';

const projectId = 'demo-michizure';
const aliceId = 'alice';
const bobId = 'bob';
const carolId = 'carol';
const groupId = 'group-one';
const otherGroupId = 'group-two';
const validInviteHash = 'a'.repeat(64);
const secondInviteHash = 'b'.repeat(64);
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
  displayName = 'User',
  groupId: membership = null,
  activeTaskSessionId = null,
  timestamp = fixedTimestamp,
} = {}) => ({
  displayName,
  photoUrl: null,
  groupId: membership,
  activeTaskSessionId,
  createdAt: timestamp,
  updatedAt: timestamp,
  schemaVersion: 1,
});

const groupData = ({
  ownerUid = aliceId,
  memberCount = 1,
  name = '朝活チーム',
  timestamp = fixedTimestamp,
} = {}) => ({
  name,
  ownerUid,
  memberCount,
  createdAt: timestamp,
  updatedAt: timestamp,
  schemaVersion: 1,
});

const memberData = ({
  uid,
  displayName = uid,
  role = 'member',
  inviteTokenHash = validInviteHash,
  timestamp = fixedTimestamp,
  extra = {},
}) => ({
  userId: uid,
  displayNameSnapshot: displayName,
  role,
  inviteTokenHash,
  joinedAt: timestamp,
  updatedAt: timestamp,
  schemaVersion: 1,
  ...extra,
});

const inviteData = ({
  targetGroupId = groupId,
  groupName = '朝活チーム',
  createdByUid = aliceId,
  expiresAt = Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)),
  revokedAt = null,
  timestamp = fixedTimestamp,
  extra = {},
} = {}) => ({
  groupId: targetGroupId,
  groupNameSnapshot: groupName,
  createdByUid,
  createdAt: timestamp,
  expiresAt,
  revokedAt,
  schemaVersion: 1,
  ...extra,
});

async function expectDenied(operation) {
  await expect(assertFails(operation)).resolves.toBeDefined();
}

async function seedUser(
  uid,
  { membership = null, displayName = uid, activeTaskSessionId = null } = {},
) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users', uid),
      userData({ displayName, groupId: membership, activeTaskSessionId }),
    );
  });
}

async function seedGroup(
  id = groupId,
  {
    ownerUid = aliceId,
    memberUids = [aliceId],
    inviteHash,
    inviteExpiresAt,
    inviteRevokedAt = null,
  } = {},
) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(
      doc(firestore, 'groups', id),
      groupData({ ownerUid, memberCount: memberUids.length }),
    );
    for (const uid of memberUids) {
      await setDoc(
        doc(firestore, 'groups', id, 'members', uid),
        memberData({
          uid,
          role: uid === ownerUid ? 'owner' : 'member',
          inviteTokenHash: uid === ownerUid ? null : validInviteHash,
        }),
      );
      await setDoc(
        doc(firestore, 'users', uid),
        userData({ displayName: uid, groupId: id }),
      );
    }
    if (inviteHash) {
      await setDoc(
        doc(firestore, 'groupInvites', inviteHash),
        inviteData({
          targetGroupId: id,
          expiresAt: inviteExpiresAt,
          revokedAt: inviteRevokedAt,
        }),
      );
    }
  });
}

async function createGroupAtomic(firestore, uid, id) {
  const batch = writeBatch(firestore);
  batch.set(
    doc(firestore, 'groups', id),
    groupData({
      ownerUid: uid,
      memberCount: 1,
      timestamp: serverTimestamp(),
    }),
  );
  batch.set(
    doc(firestore, 'groups', id, 'members', uid),
    memberData({
      uid,
      displayName: uid,
      role: 'owner',
      inviteTokenHash: null,
      timestamp: serverTimestamp(),
    }),
  );
  batch.update(doc(firestore, 'users', uid), {
    groupId: id,
    updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

async function createInvite(firestore, uid, id, hash = validInviteHash) {
  return setDoc(
    doc(firestore, 'groupInvites', hash),
    inviteData({
      targetGroupId: id,
      createdByUid: uid,
      timestamp: serverTimestamp(),
    }),
  );
}

async function joinGroupTransaction(
  firestore,
  uid,
  id = groupId,
  hash = validInviteHash,
) {
  const userReference = doc(firestore, 'users', uid);
  const inviteReference = doc(firestore, 'groupInvites', hash);
  const groupReference = doc(firestore, 'groups', id);
  const memberReference = doc(firestore, 'groups', id, 'members', uid);
  return runTransaction(firestore, async (transaction) => {
    await transaction.get(userReference);
    await transaction.get(inviteReference);
    transaction.set(
      memberReference,
      memberData({
        uid,
        displayName: uid,
        inviteTokenHash: hash,
        timestamp: serverTimestamp(),
      }),
    );
    transaction.update(groupReference, {
      memberCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    transaction.update(userReference, {
      groupId: id,
      updatedAt: serverTimestamp(),
    });
  });
}

async function leaveGroupTransaction(firestore, uid, id = groupId) {
  const userReference = doc(firestore, 'users', uid);
  const groupReference = doc(firestore, 'groups', id);
  const memberReference = doc(firestore, 'groups', id, 'members', uid);
  return runTransaction(firestore, async (transaction) => {
    await transaction.get(userReference);
    const groupSnapshot = await transaction.get(groupReference);
    await transaction.get(memberReference);
    transaction.delete(memberReference);
    transaction.update(groupReference, {
      memberCount: groupSnapshot.data().memberCount - 1,
      updatedAt: serverTimestamp(),
    });
    transaction.update(userReference, {
      groupId: null,
      updatedAt: serverTimestamp(),
    });
  });
}

async function transferOwnershipTransaction(
  firestore,
  oldOwnerUid,
  newOwnerUid,
  id = groupId,
) {
  const groupReference = doc(firestore, 'groups', id);
  const oldOwnerReference = doc(
    firestore,
    'groups',
    id,
    'members',
    oldOwnerUid,
  );
  const newOwnerReference = doc(
    firestore,
    'groups',
    id,
    'members',
    newOwnerUid,
  );
  return runTransaction(firestore, async (transaction) => {
    await transaction.get(groupReference);
    await transaction.get(oldOwnerReference);
    await transaction.get(newOwnerReference);
    transaction.update(groupReference, {
      ownerUid: newOwnerUid,
      updatedAt: serverTimestamp(),
    });
    transaction.update(oldOwnerReference, {
      role: 'member',
      updatedAt: serverTimestamp(),
    });
    transaction.update(newOwnerReference, {
      role: 'owner',
      updatedAt: serverTimestamp(),
    });
  });
}

describe('group atomic workflows', () => {
  test('creates group, owner membership, and user pointer atomically', async () => {
    await seedUser(aliceId);

    await assertSucceeds(
      createGroupAtomic(firestoreAs(aliceId), aliceId, groupId),
    );
  });

  test('denies group creation when already in a group', async () => {
    await seedGroup();

    await expectDenied(
      createGroupAtomic(firestoreAs(aliceId), aliceId, otherGroupId),
    );
  });

  test('joins with a valid invite and updates all three documents', async () => {
    await seedGroup(groupId, {
      inviteHash: validInviteHash,
    });
    await seedUser(bobId);

    await assertSucceeds(
      joinGroupTransaction(firestoreAs(bobId), bobId),
    );
  });

  test('denies a second group join', async () => {
    await seedGroup(groupId, {
      inviteHash: validInviteHash,
    });
    await seedGroup(otherGroupId, {
      ownerUid: carolId,
      memberUids: [carolId, bobId],
      inviteHash: secondInviteHash,
    });

    await expectDenied(
      joinGroupTransaction(
        firestoreAs(bobId),
        bobId,
        groupId,
        validInviteHash,
      ),
    );
  });

  test('concurrent joins by one user can only select one group', async () => {
    await seedGroup(groupId, {
      inviteHash: validInviteHash,
    });
    await seedGroup(otherGroupId, {
      ownerUid: carolId,
      memberUids: [carolId],
      inviteHash: secondInviteHash,
    });
    await seedUser(bobId);

    const results = await Promise.allSettled([
      joinGroupTransaction(
        firestoreAs(bobId),
        bobId,
        groupId,
        validInviteHash,
      ),
      joinGroupTransaction(
        firestoreAs(bobId),
        bobId,
        otherGroupId,
        secondInviteHash,
      ),
    ]);

    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      const userSnapshot = await getDoc(doc(firestore, 'users', bobId));
      const memberships = await Promise.all([
        getDoc(doc(firestore, 'groups', groupId, 'members', bobId)),
        getDoc(doc(firestore, 'groups', otherGroupId, 'members', bobId)),
      ]);
      expect([groupId, otherGroupId]).toContain(userSnapshot.data().groupId);
      expect(memberships.filter((snapshot) => snapshot.exists())).toHaveLength(1);
    });
  });

  test('denies the 41st member', async () => {
    const memberUids = [
      aliceId,
      ...Array.from({ length: 39 }, (_, index) => `member-${index}`),
    ];
    await seedGroup(groupId, {
      memberUids,
      inviteHash: validInviteHash,
    });
    await seedUser(bobId);

    await expectDenied(
      joinGroupTransaction(firestoreAs(bobId), bobId),
    );
  });

  test('concurrent joins at 39 members never exceed 40', async () => {
    const memberUids = [
      aliceId,
      ...Array.from({ length: 38 }, (_, index) => `member-${index}`),
    ];
    await seedGroup(groupId, {
      memberUids,
      inviteHash: validInviteHash,
    });
    await seedUser(bobId);
    await seedUser(carolId);

    const results = await Promise.allSettled([
      joinGroupTransaction(firestoreAs(bobId), bobId),
      joinGroupTransaction(firestoreAs(carolId), carolId),
    ]);

    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      const groupSnapshot = await getDoc(doc(firestore, 'groups', groupId));
      const memberSnapshots = await getDocs(
        collection(firestore, 'groups', groupId, 'members'),
      );
      expect(groupSnapshot.data().memberCount).toBe(40);
      expect(memberSnapshots.size).toBe(40);
    });
  });

  test('a member leaves with member, count, and user pointer updates', async () => {
    await seedGroup(groupId, {
      memberUids: [aliceId, bobId],
    });

    await assertSucceeds(
      leaveGroupTransaction(firestoreAs(bobId), bobId),
    );
  });

  test('a member with an active task cannot leave', async () => {
    await seedGroup(groupId, {
      memberUids: [aliceId, bobId],
    });
    await seedUser(bobId, {
      membership: groupId,
      activeTaskSessionId: 'running-task',
    });

    await expectDenied(
      leaveGroupTransaction(firestoreAs(bobId), bobId),
    );
  });

  test('owner cannot leave before ownership transfer', async () => {
    await seedGroup(groupId, {
      memberUids: [aliceId, bobId],
    });

    await expectDenied(
      leaveGroupTransaction(firestoreAs(aliceId), aliceId),
    );
  });

  test('owner transfer updates group and both member roles atomically', async () => {
    await seedGroup(groupId, {
      memberUids: [aliceId, bobId],
    });

    await assertSucceeds(
      transferOwnershipTransaction(
        firestoreAs(aliceId),
        aliceId,
        bobId,
      ),
    );
    await assertSucceeds(
      leaveGroupTransaction(firestoreAs(aliceId), aliceId),
    );
  });
});

describe('group authorization and schema', () => {
  test('denies unauthenticated group read and create', async () => {
    await seedGroup();
    await seedUser(bobId);
    await expectDenied(
      getDoc(doc(unauthenticatedFirestore(), 'groups', groupId)),
    );
    await expectDenied(
      createGroupAtomic(unauthenticatedFirestore(), bobId, otherGroupId),
    );
  });

  test('member can read group and member list', async () => {
    await seedGroup(groupId, {
      memberUids: [aliceId, bobId],
    });
    const bob = firestoreAs(bobId);

    await assertSucceeds(getDoc(doc(bob, 'groups', groupId)));
    await assertSucceeds(
      getDocs(collection(bob, 'groups', groupId, 'members')),
    );
  });

  test('non-member and another-group member cannot read the group', async () => {
    await seedGroup();
    await seedUser(bobId);
    await seedGroup(otherGroupId, {
      ownerUid: carolId,
      memberUids: [carolId],
    });

    await expectDenied(getDoc(doc(firestoreAs(bobId), 'groups', groupId)));
    await expectDenied(getDoc(doc(firestoreAs(carolId), 'groups', groupId)));
  });

  test('denies inconsistent groupId during join', async () => {
    await seedGroup(groupId, {
      inviteHash: validInviteHash,
    });
    await seedGroup(otherGroupId, {
      ownerUid: carolId,
      memberUids: [carolId],
    });
    await seedUser(bobId);
    const bob = firestoreAs(bobId);
    const batch = writeBatch(bob);
    batch.set(
      doc(bob, 'groups', groupId, 'members', bobId),
      memberData({
        uid: bobId,
        displayName: bobId,
        timestamp: serverTimestamp(),
      }),
    );
    batch.update(doc(bob, 'groups', groupId), {
      memberCount: 2,
      updatedAt: serverTimestamp(),
    });
    batch.update(doc(bob, 'users', bobId), {
      groupId: otherGroupId,
      updatedAt: serverTimestamp(),
    });

    await expectDenied(batch.commit());
  });

  test('denies membership identity spoofing independently', async () => {
    await seedGroup(groupId, {
      inviteHash: validInviteHash,
    });
    await seedUser(bobId);
    const bob = firestoreAs(bobId);
    const batch = writeBatch(bob);
    batch.set(
      doc(bob, 'groups', groupId, 'members', bobId),
      memberData({
        uid: bobId,
        displayName: bobId,
        timestamp: serverTimestamp(),
        extra: { userId: carolId },
      }),
    );
    batch.update(doc(bob, 'groups', groupId), {
      memberCount: 2,
      updatedAt: serverTimestamp(),
    });
    batch.update(doc(bob, 'users', bobId), {
      groupId,
      updatedAt: serverTimestamp(),
    });

    await expectDenied(batch.commit());
  });

  test('denies a display name snapshot that differs from the user profile', async () => {
    await seedGroup(groupId, {
      inviteHash: validInviteHash,
    });
    await seedUser(bobId, { displayName: '正しい名前' });
    const bob = firestoreAs(bobId);
    const batch = writeBatch(bob);
    batch.set(
      doc(bob, 'groups', groupId, 'members', bobId),
      memberData({
        uid: bobId,
        displayName: '偽の名前',
        timestamp: serverTimestamp(),
      }),
    );
    batch.update(doc(bob, 'groups', groupId), {
      memberCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    batch.update(doc(bob, 'users', bobId), {
      groupId,
      updatedAt: serverTimestamp(),
    });

    await expectDenied(batch.commit());
  });

  test('denies protected member identity changes', async () => {
    await seedGroup();
    await expectDenied(
      updateDoc(
        doc(firestoreAs(aliceId), 'groups', groupId, 'members', aliceId),
        {
          userId: bobId,
          updatedAt: serverTimestamp(),
        },
      ),
    );
  });

  test('denies extra group and member fields', async () => {
    await seedGroup();
    const alice = firestoreAs(aliceId);
    await expectDenied(
      updateDoc(doc(alice, 'groups', groupId), {
        unexpected: true,
        updatedAt: serverTimestamp(),
      }),
    );
    await expectDenied(
      updateDoc(doc(alice, 'groups', groupId, 'members', aliceId), {
        unexpected: true,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  test('denies group, invite, and standalone member deletion', async () => {
    await seedGroup(groupId, {
      memberUids: [aliceId, bobId],
      inviteHash: validInviteHash,
    });
    const alice = firestoreAs(aliceId);
    await expectDenied(deleteDoc(doc(alice, 'groups', groupId)));
    await expectDenied(
      deleteDoc(doc(alice, 'groupInvites', validInviteHash)),
    );
    await expectDenied(
      deleteDoc(doc(firestoreAs(bobId), 'groups', groupId, 'members', bobId)),
    );
  });

  test('denies unscoped group and invite list queries', async () => {
    await seedGroup();
    const alice = firestoreAs(aliceId);
    await expectDenied(getDocs(collection(alice, 'groups')));
    await expectDenied(getDocs(collection(alice, 'groupInvites')));
  });
});

describe('invite and profile snapshot rules', () => {
  test('member creates, outsider gets, and creator revokes an invite', async () => {
    await seedGroup();
    await seedUser(bobId);
    const alice = firestoreAs(aliceId);

    await assertSucceeds(
      createInvite(alice, aliceId, groupId),
    );
    await assertSucceeds(
      getDoc(doc(firestoreAs(bobId), 'groupInvites', validInviteHash)),
    );
    await assertSucceeds(
      updateDoc(doc(alice, 'groupInvites', validInviteHash), {
        revokedAt: serverTimestamp(),
      }),
    );
  });

  test('denies invite extra fields and raw token storage', async () => {
    await seedGroup();
    const alice = firestoreAs(aliceId);
    await expectDenied(
      setDoc(
        doc(alice, 'groupInvites', validInviteHash),
        inviteData({
          timestamp: serverTimestamp(),
          extra: { rawToken: 'must-not-be-stored' },
        }),
      ),
    );
  });

  test('denies expired and revoked invite joins', async () => {
    await seedGroup(groupId, {
      inviteHash: validInviteHash,
      inviteExpiresAt: Timestamp.fromDate(
        new Date(Date.now() - 60 * 1000),
      ),
    });
    await seedUser(bobId);
    await expectDenied(
      joinGroupTransaction(firestoreAs(bobId), bobId),
    );

    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), 'groupInvites', validInviteHash),
        inviteData({
          revokedAt: fixedTimestamp,
        }),
      );
    });
    await expectDenied(
      joinGroupTransaction(firestoreAs(bobId), bobId),
    );
  });

  test('profile and member displayNameSnapshot must update atomically', async () => {
    await seedGroup();
    const alice = firestoreAs(aliceId);
    const batch = writeBatch(alice);
    batch.update(doc(alice, 'users', aliceId), {
      displayName: '野々村 奏',
      updatedAt: serverTimestamp(),
    });
    batch.update(doc(alice, 'groups', groupId, 'members', aliceId), {
      displayNameSnapshot: '野々村 奏',
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());

    await expectDenied(
      updateDoc(doc(alice, 'users', aliceId), {
        displayName: '同期なし',
        updatedAt: serverTimestamp(),
      }),
    );
  });
});
