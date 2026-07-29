package com.kren.michizure.persistence

import android.content.Context
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

interface LockStateStore {
    suspend fun read(): PersistedLockState

    suspend fun update(
        transform: (PersistedLockState) -> PersistedLockState,
    ): PersistedLockState
}

class LockObligationStore(context: Context) : LockStateStore {
    private val dataStore = context.lockObligationDataStore

    override suspend fun read(): PersistedLockState {
        return decode(dataStore.data.first())
    }

    override suspend fun update(
        transform: (PersistedLockState) -> PersistedLockState,
    ): PersistedLockState {
        var updated: PersistedLockState? = null
        dataStore.edit { preferences ->
            val next = transform(decode(preferences))
            validate(next)
            preferences[obligationsKey] =
                next.obligations.values.mapTo(linkedSetOf(), LockObligationCodec::encode)
            preferences[ownedSuspensionsKey] = next.ownedSuspensions.toSet()
            updated = next
        }
        return checkNotNull(updated)
    }

    private fun decode(preferences: Preferences): PersistedLockState {
        val obligations =
            preferences[obligationsKey]
                .orEmpty()
                .map(LockObligationCodec::decode)
                .associateBy { it.debtId }
        return PersistedLockState(
            obligations = obligations,
            ownedSuspensions = preferences[ownedSuspensionsKey].orEmpty().toSet(),
        ).also(::validate)
    }

    private fun validate(state: PersistedLockState) {
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

    companion object {
        private val obligationsKey = stringSetPreferencesKey("obligations_v1")
        private val ownedSuspensionsKey =
            stringSetPreferencesKey("owned_suspensions_v1")
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
