package com.kren.michizure.platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.provider.Settings
import com.kren.michizure.enforcement.AndroidPackageCatalog
import com.kren.michizure.enforcement.LockCoordinator
import com.kren.michizure.enforcement.LockCoordinatorException
import com.kren.michizure.enforcement.LockReconciliationResult
import com.kren.michizure.enforcement.LockRemoteStatus
import com.kren.michizure.enforcement.PackageCatalog
import com.kren.michizure.monitoring.AndroidTaskGuardClock
import com.kren.michizure.monitoring.TaskGuardFailureReason
import com.kren.michizure.monitoring.TaskGuardService
import com.kren.michizure.monitoring.TaskGuardTerminal
import com.kren.michizure.monitoring.TaskGuardTerminalKind
import com.kren.michizure.persistence.NativeTaskRecord
import com.kren.michizure.persistence.SelectedPackageStore
import com.kren.michizure.persistence.NativeTaskStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class DeviceControlMethodHandler(
    private val context: Context,
    private val capabilitiesProvider: DeviceCapabilitiesProvider =
        DeviceCapabilitiesProvider(context),
    private val packageCatalog: PackageCatalog = AndroidPackageCatalog(context),
    private val selectedPackageStore: SelectedPackageStore =
        SelectedPackageStore(context),
    private val nativeTaskStore: NativeTaskStore = NativeTaskStore(context),
    private val lockCoordinator: LockCoordinator = LockCoordinator(context),
) : MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!DeviceControlContract.hasSupportedVersion(call.arguments)) {
            result.error(
                DeviceControlContract.ERROR_CHANNEL_CONTRACT_MISMATCH,
                "The app and Android bridge versions do not match.",
                DeviceControlContract.versionedPayload(),
            )
            return
        }

        when (call.method) {
            DeviceControlContract.METHOD_GET_CAPABILITIES -> runSafely(result) {
                capabilitiesProvider.getCapabilities()
            }
            DeviceControlContract.METHOD_OPEN_USAGE_ACCESS_SETTINGS -> {
                runSafely(result) {
                    openSettings(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    DeviceControlContract.versionedPayload()
                }
            }
            DeviceControlContract.METHOD_OPEN_NOTIFICATION_SETTINGS -> {
                runSafely(result) {
                    openSettings(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                            .setData(Uri.parse("package:${context.packageName}")),
                    )
                    DeviceControlContract.versionedPayload()
                }
            }
            DeviceControlContract.METHOD_LIST_LOCKABLE_APPS -> {
                runSafely(result) {
                    val apps =
                        packageCatalog.listLockableApps().map { app ->
                            mapOf(
                                "packageName" to app.packageName,
                                "label" to app.label,
                                "isSelectable" to app.isSelectable,
                                "protectionReason" to app.protectionReason?.wireValue,
                            )
                        }
                    DeviceControlContract.versionedPayload(mapOf("apps" to apps))
                }
            }
            DeviceControlContract.METHOD_GET_SELECTED_PACKAGES -> {
                scope.launch {
                    runCatching {
                        val stored = selectedPackageStore.read()
                        val selectable =
                            packageCatalog.listLockableApps()
                                .filter { it.isSelectable }
                                .mapTo(linkedSetOf()) { it.packageName }
                        val reconciled = stored.intersect(selectable)
                        if (reconciled != stored) {
                            selectedPackageStore.save(reconciled)
                        }
                        reconciled
                    }
                        .onSuccess { packages ->
                            postSuccess(
                                result,
                                DeviceControlContract.versionedPayload(
                                    mapOf("packageNames" to packages.sorted()),
                                ),
                            )
                        }
                        .onFailure { postNativeStateError(result) }
                }
            }
            DeviceControlContract.METHOD_SAVE_SELECTED_PACKAGES -> {
                val packageNames = parsePackageNames(call.arguments)
                if (packageNames == null) {
                    result.error(
                        DeviceControlContract.ERROR_CHANNEL_CONTRACT_MISMATCH,
                        "The selected package payload is invalid.",
                        DeviceControlContract.versionedPayload(),
                    )
                    return
                }
                val catalogByPackage =
                    runCatching {
                        packageCatalog.listLockableApps().associateBy { it.packageName }
                    }.getOrElse {
                        postNativeUnavailable(result)
                        return
                    }
                val unavailable =
                    packageNames.firstOrNull { catalogByPackage[it] == null }
                if (unavailable != null) {
                    result.error(
                        DeviceControlContract.ERROR_PACKAGE_NOT_INSTALLED,
                        "A selected app is no longer available.",
                        DeviceControlContract.versionedPayload(),
                    )
                    return
                }
                val protectedPackage =
                    packageNames.firstOrNull {
                        catalogByPackage.getValue(it).isSelectable.not()
                    }
                if (protectedPackage != null) {
                    result.error(
                        DeviceControlContract.ERROR_PACKAGE_PROTECTED,
                        "A protected system app cannot be selected.",
                        DeviceControlContract.versionedPayload(),
                    )
                    return
                }
                scope.launch {
                    runCatching { selectedPackageStore.save(packageNames) }
                        .onSuccess {
                            postSuccess(
                                result,
                                DeviceControlContract.versionedPayload(
                                    mapOf("packageNames" to packageNames.sorted()),
                                ),
                            )
                        }
                        .onFailure { postNativeStateError(result) }
                    }
            }
            DeviceControlContract.METHOD_START_TASK_GUARD -> {
                val command = parseStartTaskGuard(call.arguments)
                if (command == null) {
                    postContractError(result, "The Task Guard payload is invalid.")
                    return
                }
                scope.launch {
                    startTaskGuard(command, result)
                }
            }
            DeviceControlContract.METHOD_STOP_TASK_GUARD -> {
                val taskSessionId = parseRequiredString(call.arguments, "taskSessionId")
                if (taskSessionId == null) {
                    postContractError(result, "The Task Guard stop payload is invalid.")
                    return
                }
                scope.launch {
                    runCatching {
                        nativeTaskStore.stop(taskSessionId)
                    }.onSuccess { stopped ->
                        TaskGuardService.stop(context)
                        postSuccess(
                            result,
                            DeviceControlContract.versionedPayload(
                                mapOf(
                                    "taskSessionId" to taskSessionId,
                                    "isRunning" to false,
                                    "changed" to stopped,
                                ),
                            ),
                        )
                    }.onFailure {
                        postNativeStateError(result)
                    }
                }
            }
            DeviceControlContract.METHOD_GET_TASK_GUARD_STATE -> {
                scope.launch {
                    runCatching {
                        nativeTaskStore.readTask() to nativeTaskStore.readPendingEvent()
                    }.onSuccess { (task, pendingEvent) ->
                        postSuccess(
                            result,
                            DeviceControlContract.versionedPayload(
                                mapOf(
                                    "taskSessionId" to task?.taskSessionId,
                                    "isRunning" to (task != null && pendingEvent == null),
                                    "hasPendingEvent" to (pendingEvent != null),
                                ),
                            ),
                        )
                        pendingEvent?.let(TaskEventBus::emit)
                    }.onFailure {
                        postNativeStateError(result)
                    }
                }
            }
            DeviceControlContract.METHOD_ACK_TASK_EVENT -> {
                val eventId = parseRequiredString(call.arguments, "eventId")
                if (eventId == null) {
                    postContractError(result, "The Task event acknowledgement is invalid.")
                    return
                }
                scope.launch {
                    runCatching { nativeTaskStore.acknowledge(eventId) }
                        .onSuccess { acknowledged ->
                            postSuccess(
                                result,
                                DeviceControlContract.versionedPayload(
                                    mapOf("acknowledged" to acknowledged),
                                ),
                            )
                        }
                        .onFailure { postNativeStateError(result) }
                }
            }
            DeviceControlContract.METHOD_APPLY_LOCK_OBLIGATION -> {
                val command = parseApplyLockObligation(call.arguments)
                if (command == null) {
                    postContractError(result, "The lock obligation payload is invalid.")
                    return
                }
                scope.launch {
                    runCatching {
                        lockCoordinator.applyObligation(
                            debtId = command.debtId,
                            taskSessionId = command.taskSessionId,
                            createdWallMs = command.createdAtEpochMs,
                            expiresWallMs = command.expiresAtEpochMs,
                        )
                    }.onSuccess {
                        postSuccess(result, lockResultPayload(it))
                    }.onFailure {
                        postLockError(result, it)
                    }
                }
            }
            DeviceControlContract.METHOD_GET_LOCK_STATE,
            DeviceControlContract.METHOD_RECONCILE_LOCKS,
            -> {
                scope.launch {
                    runCatching { lockCoordinator.reconcile() }
                        .onSuccess {
                            postSuccess(result, lockResultPayload(it))
                        }
                        .onFailure {
                            postLockError(result, it)
                        }
                }
            }
            DeviceControlContract.METHOD_RELEASE_LOCK_OBLIGATION -> {
                val command = parseReleaseLockObligation(call.arguments)
                if (command == null) {
                    postContractError(result, "The lock release payload is invalid.")
                    return
                }
                scope.launch {
                    runCatching {
                        lockCoordinator.resolveObligation(
                            debtId = command.debtId,
                            status = command.status,
                        )
                    }.onSuccess {
                        postSuccess(result, lockResultPayload(it))
                    }.onFailure {
                        postLockError(result, it)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun close() {
        scope.cancel()
    }

    private fun openSettings(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun runSafely(
        result: MethodChannel.Result,
        action: () -> Map<String, Any?>,
    ) {
        runCatching(action)
            .onSuccess(result::success)
            .onFailure { postNativeUnavailable(result) }
    }

    private fun parsePackageNames(arguments: Any?): Set<String>? {
        val payload = arguments as? Map<*, *> ?: return null
        val values = payload["packageNames"] as? List<*> ?: return null
        if (values.any { it !is String || it.isBlank() }) {
            return null
        }
        return values.filterIsInstance<String>().toSet()
    }

    private suspend fun startTaskGuard(
        command: StartTaskGuardCommand,
        result: MethodChannel.Result,
    ) {
        val selectedPackages =
            runCatching { selectedPackageStore.read() }.getOrElse {
                postNativeStateError(result)
                return
            }
        if (selectedPackages.isEmpty()) {
            postTypedError(
                result,
                DeviceControlContract.ERROR_NATIVE_STATE_CORRUPT,
                "No lock target snapshot is available.",
            )
            return
        }

        val taskClock = AndroidTaskGuardClock(context)
        val nowWallMs = taskClock.wallTimeMs()
        val nowElapsedMs = taskClock.elapsedRealtimeMs()
        val record =
            NativeTaskRecord(
                taskSessionId = command.taskSessionId,
                startedWallMs = command.startedAtEpochMs,
                expectedEndWallMs = command.expectedEndAtEpochMs,
                startedElapsedMs =
                    nowElapsedMs - (nowWallMs - command.startedAtEpochMs),
                expectedEndElapsedMs =
                    nowElapsedMs + (command.expectedEndAtEpochMs - nowWallMs),
                bootCount = taskClock.bootCount(),
                guardConfigVersion = command.guardConfigVersion,
                lockTargetsAtStart = selectedPackages,
            )
        val persisted =
            runCatching { nativeTaskStore.start(record) }.getOrElse {
                postNativeStateError(result)
                return
            }
        val pendingEvent =
            runCatching { nativeTaskStore.readPendingEvent() }.getOrElse {
                postNativeStateError(result)
                return
            }
        if (pendingEvent != null) {
            TaskEventBus.emit(pendingEvent)
            postSuccess(
                result,
                DeviceControlContract.versionedPayload(
                    mapOf(
                        "taskSessionId" to persisted.taskSessionId,
                        "isRunning" to false,
                        "hasPendingEvent" to true,
                    ),
                ),
            )
            return
        }
        val capabilities =
            runCatching { capabilitiesProvider.getCapabilities() }.getOrElse {
                persistCapabilityFailure(persisted, taskClock)
                postNativeUnavailable(result)
                return
            }
        val capabilityError =
            when {
                capabilities["isDeviceOwner"] != true ->
                    DeviceControlContract.ERROR_NOT_DEVICE_OWNER
                capabilities["hasUsageAccess"] != true ->
                    DeviceControlContract.ERROR_USAGE_ACCESS_MISSING
                capabilities["hasNotificationPermission"] != true ->
                    DeviceControlContract.ERROR_NOTIFICATION_PERMISSION_MISSING
                capabilities["isUserUnlocked"] != true ||
                    Build.VERSION.SDK_INT < 29 ->
                    DeviceControlContract.ERROR_NATIVE_UNAVAILABLE
                else -> null
            }
        if (capabilityError != null) {
            persistCapabilityFailure(persisted, taskClock)
            postTypedError(
                result,
                capabilityError,
                "Task monitoring is not available on this device.",
            )
            return
        }
        runCatching { TaskGuardService.start(context) }
            .onSuccess {
                postSuccess(
                    result,
                    DeviceControlContract.versionedPayload(
                        mapOf(
                            "taskSessionId" to persisted.taskSessionId,
                            "isRunning" to true,
                            "hasPendingEvent" to false,
                        ),
                    ),
                )
            }
            .onFailure {
                persistCapabilityFailure(persisted, taskClock)
                postTypedError(
                    result,
                    DeviceControlContract.ERROR_FOREGROUND_SERVICE_START_DENIED,
                    "The Task monitoring service could not be started.",
                )
            }
    }

    private suspend fun persistCapabilityFailure(
        task: NativeTaskRecord,
        taskClock: AndroidTaskGuardClock,
    ) {
        val terminal =
            TaskGuardTerminal(
                kind = TaskGuardTerminalKind.TASK_FAILED,
                failureReason = TaskGuardFailureReason.MONITOR_CAPABILITY_LOST,
                originElapsedMs = taskClock.elapsedRealtimeMs(),
            )
        runCatching {
            nativeTaskStore.commitTerminal(task.taskSessionId, terminal)
        }.getOrNull()?.let(TaskEventBus::emit)
    }

    private fun parseStartTaskGuard(arguments: Any?): StartTaskGuardCommand? {
        val payload = arguments as? Map<*, *> ?: return null
        val taskSessionId = payload["taskSessionId"] as? String ?: return null
        val startedAtEpochMs = (payload["startedAtEpochMs"] as? Number)?.toLong()
            ?: return null
        val expectedEndAtEpochMs =
            (payload["expectedEndAtEpochMs"] as? Number)?.toLong() ?: return null
        val guardConfigVersion =
            (payload["guardConfigVersion"] as? Number)?.toInt() ?: return null
        if (taskSessionId.isBlank() ||
            startedAtEpochMs < 0 ||
            expectedEndAtEpochMs < startedAtEpochMs ||
            guardConfigVersion != 1
        ) {
            return null
        }
        return StartTaskGuardCommand(
            taskSessionId = taskSessionId,
            startedAtEpochMs = startedAtEpochMs,
            expectedEndAtEpochMs = expectedEndAtEpochMs,
            guardConfigVersion = guardConfigVersion,
        )
    }

    private fun parseRequiredString(arguments: Any?, key: String): String? {
        val value = (arguments as? Map<*, *>)?.get(key) as? String
        return value?.takeIf(String::isNotBlank)
    }

    private fun parseApplyLockObligation(arguments: Any?): ApplyLockCommand? {
        val payload = arguments as? Map<*, *> ?: return null
        val debtId = payload["debtId"] as? String ?: return null
        val taskSessionId = payload["taskSessionId"] as? String ?: return null
        val createdAtEpochMs =
            (payload["createdAtEpochMs"] as? Number)?.toLong() ?: return null
        val expiresAtEpochMs =
            (payload["expiresAtEpochMs"] as? Number)?.toLong() ?: return null
        if (debtId.isBlank() ||
            taskSessionId.isBlank() ||
            createdAtEpochMs < 0 ||
            expiresAtEpochMs < createdAtEpochMs
        ) {
            return null
        }
        return ApplyLockCommand(
            debtId = debtId,
            taskSessionId = taskSessionId,
            createdAtEpochMs = createdAtEpochMs,
            expiresAtEpochMs = expiresAtEpochMs,
        )
    }

    private fun parseReleaseLockObligation(arguments: Any?): ReleaseLockCommand? {
        val payload = arguments as? Map<*, *> ?: return null
        val debtId = payload["debtId"] as? String ?: return null
        val status =
            when (payload["resolution"]) {
                LockRemoteStatus.COMPLETED.wireValue -> LockRemoteStatus.COMPLETED
                LockRemoteStatus.EXPIRED.wireValue -> LockRemoteStatus.EXPIRED
                else -> return null
            }
        return debtId.takeIf(String::isNotBlank)?.let {
            ReleaseLockCommand(it, status)
        }
    }

    private fun lockResultPayload(
        result: LockReconciliationResult,
    ): Map<String, Any?> {
        val obligations =
            result.state.obligations.values
                .sortedBy { it.expiresWallMs }
                .map { obligation ->
                    mapOf(
                        "debtId" to obligation.debtId,
                        "taskSessionId" to obligation.taskSessionId,
                        "expiresAtEpochMs" to obligation.expiresWallMs,
                        "remoteStatus" to obligation.remoteStatus.wireValue,
                        "localState" to obligation.localState.wireValue,
                        "targetCount" to obligation.packageNames.size,
                        "enforcedCount" to
                            obligation.packageNames
                                .intersect(result.state.ownedSuspensions)
                                .size,
                        "failedCount" to obligation.failedPackages.size,
                        "errorCode" to obligation.lastErrorCode,
                    )
                }
        return DeviceControlContract.versionedPayload(
            mapOf(
                "obligations" to obligations,
                "effectiveTargetCount" to result.desiredPackages.size,
                "ownedSuspensionCount" to result.state.ownedSuspensions.size,
                "appliedCount" to result.appliedPackages.size,
                "releasedCount" to result.releasedPackages.size,
                "failedCount" to result.failedPackages.size,
                "nextDeadlineEpochMs" to result.nextDeadlineWallMs,
            ),
        )
    }

    private fun postLockError(
        result: MethodChannel.Result,
        error: Throwable,
    ) {
        val code =
            when (error) {
                is LockCoordinatorException -> error.code
                else -> DeviceControlContract.ERROR_NATIVE_STATE_CORRUPT
            }
        postTypedError(
            result,
            code,
            "The Android app lock state could not be reconciled.",
        )
    }

    private fun postSuccess(
        result: MethodChannel.Result,
        payload: Map<String, Any?>,
    ) {
        mainHandler.post { result.success(payload) }
    }

    private fun postNativeStateError(result: MethodChannel.Result) {
        mainHandler.post {
            result.error(
                DeviceControlContract.ERROR_NATIVE_STATE_CORRUPT,
                "The local app selection could not be read or saved.",
                DeviceControlContract.versionedPayload(),
            )
        }
    }

    private fun postContractError(
        result: MethodChannel.Result,
        message: String,
    ) {
        postTypedError(
            result,
            DeviceControlContract.ERROR_CHANNEL_CONTRACT_MISMATCH,
            message,
        )
    }

    private fun postTypedError(
        result: MethodChannel.Result,
        code: String,
        message: String,
    ) {
        mainHandler.post {
            result.error(
                code,
                message,
                DeviceControlContract.versionedPayload(),
            )
        }
    }

    private fun postNativeUnavailable(result: MethodChannel.Result) {
        result.error(
            DeviceControlContract.ERROR_NATIVE_UNAVAILABLE,
            "The requested Android operation is unavailable.",
            DeviceControlContract.versionedPayload(),
        )
    }
}

private data class StartTaskGuardCommand(
    val taskSessionId: String,
    val startedAtEpochMs: Long,
    val expectedEndAtEpochMs: Long,
    val guardConfigVersion: Int,
)

private data class ApplyLockCommand(
    val debtId: String,
    val taskSessionId: String,
    val createdAtEpochMs: Long,
    val expiresAtEpochMs: Long,
)

private data class ReleaseLockCommand(
    val debtId: String,
    val status: LockRemoteStatus,
)
