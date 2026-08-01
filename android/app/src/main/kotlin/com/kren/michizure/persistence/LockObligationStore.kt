package com.kren.michizure.persistence

import android.content.Context
import android.os.Build
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.kren.michizure.enforcement.LockLocalState
import com.kren.michizure.enforcement.LockObligation
import com.kren.michizure.enforcement.LockRemoteStatus
import com.kren.michizure.enforcement.PersistedLockState
import kotlinx.coroutines.flow.first
import java.nio.charset.StandardCharsets
import java.util.Base64

private val Context.lockObligationDataStore by preferencesDataStore(
    name = "lock_obligations",
)

private val Context.bootLockSnapshotDataStore by preferencesDataStore(
    name = "boot_lock_snapshot",
)

interface LockStateStore {
    suspend fun read(): PersistedLockState

    suspend fun update(
        transform: (PersistedLockState) -> PersistedLockState,
    ): PersistedLockState
}

class LockObligationStore(context: Context) : LockStateStore {
    private val dataStore = context.lockObligationDataStore
    private val bootStore = DeviceProtectedLockStateStore(context)

    override suspend fun read(): PersistedLockState {
        return try {
            decodeLockState(dataStore.data.first())
        } catch (error: LockObligationStoreException) {
            val snapshot = bootStore.read()
            if (snapshot.obligations.isEmpty() && snapshot.ownedSuspensions.isEmpty()) {
                throw error
            }
            replaceCredentialState(snapshot)
            snapshot
        }
    }

    override suspend fun update(
        transform: (PersistedLockState) -> PersistedLockState,
    ): PersistedLockState {
        val current = read()
        val next = transform(current)
        validateLockState(next)
        replaceCredentialState(next)
        bootStore.replace(minimalBootSnapshot(next))
        return next
    }

    private suspend fun replaceCredentialState(state: PersistedLockState) {
        dataStore.edit { preferences ->
            writeLockState(preferences, state)
        }
    }
}

class DeviceProtectedLockStateStore(context: Context) : LockStateStore {
    private val storageContext =
        if (Build.VERSION.SDK_INT >= 24) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
    private val dataStore = storageContext.bootLockSnapshotDataStore

    override suspend fun read(): PersistedLockState {
        return decodeLockState(dataStore.data.first())
    }

    override suspend fun update(
        transform: (PersistedLockState) -> PersistedLockState,
    ): PersistedLockState {
        val next = transform(read())
        replace(next)
        return next
    }

    suspend fun replace(state: PersistedLockState) {
        validateLockState(state)
        dataStore.edit { preferences ->
            writeLockState(preferences, state)
        }
    }
}

private val obligationsKey = stringSetPreferencesKey("obligations_v1")
private val ownedSuspensionsKey =
    stringSetPreferencesKey("owned_suspensions_v1")

private fun decodeLockState(preferences: Preferences): PersistedLockState {
    val encoded = preferences[obligationsKey].orEmpty()
    val obligations =
        encoded
            .map(LockObligationCodec::decode)
            .associateBy { it.debtId }
    if (obligations.size != encoded.size) {
        throw LockObligationStoreException("duplicateObligation")
    }
    return PersistedLockState(
        obligations = obligations,
        ownedSuspensions = preferences[ownedSuspensionsKey].orEmpty().toSet(),
    ).also(::validateLockState)
}

private fun writeLockState(
    preferences: androidx.datastore.preferences.core.MutablePreferences,
    state: PersistedLockState,
) {
    preferences[obligationsKey] =
        state.obligations.values.mapTo(linkedSetOf(), LockObligationCodec::encode)
    preferences[ownedSuspensionsKey] = state.ownedSuspensions.toSet()
}

private fun minimalBootSnapshot(state: PersistedLockState): PersistedLockState {
    return state.copy(
        obligations =
            state.obligations.filterValues {
                it.remoteStatus == LockRemoteStatus.ACTIVE &&
                    it.localState != LockLocalState.RELEASED
            },
    )
}

private fun validateLockState(state: PersistedLockState) {
    if (state.ownedSuspensions.any(String::isBlank) ||
        state.obligations.values.any {
            it.debtId.isBlank() ||
                it.taskSessionId.isBlank() ||
                it.packageNames.isEmpty() ||
                it.packageNames.any(String::isBlank) ||
                it.createdWallMs < 0 ||
                it.expiresWallMs < it.createdWallMs ||
                it.createdElapsedMs < 0 ||
                it.expiresElapsedMs < it.createdElapsedMs ||
                it.bootCount < 0
        }
    ) {
        throw LockObligationStoreException("invalidState")
    }
}

object LockObligationCodec {
    private const val VERSION = "1"
    private const val FIELD_SEPARATOR = "|"
    private const val SET_SEPARATOR = ","

    fun encode(value: LockObligation): String {
        return listOf(
            VERSION,
            encodeText(value.debtId),
            encodeText(value.taskSessionId),
            encodeSet(value.packageNames),
            value.createdWallMs.toString(),
            value.expiresWallMs.toString(),
            value.createdElapsedMs.toString(),
            value.expiresElapsedMs.toString(),
            value.bootCount.toString(),
            value.remoteStatus.wireValue,
            value.localState.wireValue,
            encodeSet(value.failedPackages),
            value.lastErrorCode?.let(::encodeText).orEmpty(),
        ).joinToString(FIELD_SEPARATOR)
    }

    fun decode(value: String): LockObligation {
        val fields = value.split(FIELD_SEPARATOR)
        if (fields.size != 13 || fields[0] != VERSION) {
            throw LockObligationStoreException("corruptObligation")
        }
        return try {
            LockObligation(
                debtId = decodeText(fields[1]),
                taskSessionId = decodeText(fields[2]),
                packageNames = decodeSet(fields[3]),
                createdWallMs = fields[4].toLong(),
                expiresWallMs = fields[5].toLong(),
                createdElapsedMs = fields[6].toLong(),
                expiresElapsedMs = fields[7].toLong(),
                bootCount = fields[8].toInt(),
                remoteStatus =
                    LockRemoteStatus.entries.single { it.wireValue == fields[9] },
                localState =
                    LockLocalState.entries.single { it.wireValue == fields[10] },
                failedPackages = decodeSet(fields[11]),
                lastErrorCode =
                    fields[12].takeIf(String::isNotEmpty)?.let(::decodeText),
            )
        } catch (_: Exception) {
            throw LockObligationStoreException("corruptObligation")
        }
    }

    private fun encodeSet(values: Set<String>): String {
        return values.sorted().joinToString(SET_SEPARATOR, transform = ::encodeText)
    }

    private fun decodeSet(value: String): Set<String> {
        if (value.isEmpty()) {
            return emptySet()
        }
        return value.split(SET_SEPARATOR).mapTo(linkedSetOf(), ::decodeText)
    }

    private fun encodeText(value: String): String {
        return Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(value.toByteArray(StandardCharsets.UTF_8))
    }

    private fun decodeText(value: String): String {
        return String(
            Base64.getUrlDecoder().decode(value),
            StandardCharsets.UTF_8,
        )
    }
}

class LockObligationStoreException(val code: String) : IllegalStateException(code)
