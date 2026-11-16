package com.neurocompanion.app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.health.connect.AggregateRecordsRequest
import android.health.connect.AggregateRecordsResponse
import android.health.connect.HealthConnectException
import android.health.connect.HealthConnectManager
import android.health.connect.ReadRecordsRequestUsingFilters
import android.health.connect.ReadRecordsResponse
import android.health.connect.TimeInstantRangeFilter
import android.health.connect.datatypes.HeartRateRecord
import android.health.connect.datatypes.Metadata
import android.health.connect.datatypes.SleepSessionRecord
import android.health.connect.datatypes.StepsRecord
import android.os.Handler
import android.os.Looper
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Duration
import java.time.Instant

/** Android's API-34 framework. Read-only; no health SDK dependency or minSdk change. */
@RequiresApi(34)
internal class NeuraPlatformHealthReader(private val activity: Activity) : NeuraHealthReader {
    companion object { const val PERMISSION_REQUEST = 28641 }
    private val manager = activity.getSystemService(HealthConnectManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val permissions = mapOf(
        "heart_rate" to "android.permission.health.READ_HEART_RATE",
        "steps" to "android.permission.health.READ_STEPS",
        "sleep" to "android.permission.health.READ_SLEEP",
    )
    private var foreground = false
    private var disposed = false
    private var active: ReadOperation? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var permissionTimeout: Runnable? = null
    override val available: Boolean get() = manager != null && !disposed

    private data class ReadOperation(
        val id: String, val keys: List<String>, val start: Instant, val end: Instant,
        val result: MethodChannel.Result,
        val values: MutableMap<String, Any?> = linkedMapOf(),
        var timeout: Runnable? = null,
    )

    private fun hasPermission(key: String): Boolean =
        activity.checkSelfPermission(permissions.getValue(key)) == PackageManager.PERMISSION_GRANTED

    private fun selected(call: MethodCall): List<String>? {
        val values = (call.arguments as? Map<*, *>)?.get("metrics") as? List<*> ?: return null
        if (values.isEmpty() || values.size > 3 || values.any { it !is String || it !in permissions }) return null
        val keys = values.map { it as String }
        return if (keys.distinct().size == keys.size) keys.sorted() else null
    }

    override fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") {
            val id = (call.arguments as? Map<*, *>)?.get("id") as? String
            if (active?.id == id) cancelRead()
            result.success(null)
            return
        }
        if (!available || !foreground) {
            result.error("unavailable", "Health Connect requires the foreground app.", null)
            return
        }
        when (call.method) {
            "permissions" -> result.success(permissions.keys.filter { hasPermission(it) })
            "managePermissions" -> {
                cancelRead()
                try {
                    activity.startActivity(Intent(HealthConnectManager.ACTION_MANAGE_HEALTH_PERMISSIONS)
                        .putExtra(Intent.EXTRA_PACKAGE_NAME, activity.packageName))
                    result.success(true)
                } catch (_: Exception) { result.success(false) }
            }
            "requestPermissions" -> {
                val keys = selected(call)
                if (keys == null || pendingPermission != null || active != null) {
                    result.error("invalid_request", "Choose supported data types and finish the current request.", null)
                    return
                }
                val missing = keys.filterNot { hasPermission(it) }.map { permissions.getValue(it) }
                if (missing.isEmpty()) { result.success(keys); return }
                pendingPermission = result
                val timeout = Runnable {
                    if (pendingPermission === result) {
                        pendingPermission = null
                        permissionTimeout = null
                        result.error("timeout", "Permission outcome is unconfirmed. No read was started.", null)
                    }
                }
                permissionTimeout = timeout
                handler.postDelayed(timeout, 90000)
                try {
                    activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
                } catch (_: Exception) {
                    pendingPermission = null
                    handler.removeCallbacks(timeout)
                    permissionTimeout = null
                    result.error("permission_request_failed", "The permission screen could not be opened.", null)
                }
            }
            "read" -> {
                val keys = selected(call)
                val id = (call.arguments as? Map<*, *>)?.get("id") as? String
                if (keys == null || id == null || !Regex("^[a-f0-9]{32}$").matches(id) || active != null || pendingPermission != null) {
                    result.error("invalid_request", "A new foreground read is required.", null)
                    return
                }
                val end = Instant.now()
                val op = ReadOperation(id, keys, end.minus(Duration.ofHours(24)), end, result)
                active = op
                val timeout = Runnable {
                    if (active === op) {
                        active = null
                        op.values.clear()
                        result.error("timeout", "The read could not be confirmed. No automatic retry was made.", null)
                    }
                }
                op.timeout = timeout
                handler.postDelayed(timeout, 10000)
                next(op, 0)
            }
            else -> result.notImplemented()
        }
    }

    private fun current(op: ReadOperation): Boolean = active === op && foreground && !disposed
    private inline fun accept(op: ReadOperation, block: () -> Unit) {
        if (!current(op)) return
        try { block() } catch (_: Exception) { fail(op) }
    }
    private fun range(op: ReadOperation) = TimeInstantRangeFilter.Builder()
        .setStartTime(op.start).setEndTime(op.end).build()

    private fun next(op: ReadOperation, index: Int) {
        if (!current(op)) return
        if (index == op.keys.size) {
            // Re-check OS grants before releasing any data to Flutter.
            if (op.keys.any { !hasPermission(it) && (op.values[it] as? Map<*, *>)?.get("status") == "data" }) {
                fail(op); return
            }
            active = null
            op.timeout?.let(handler::removeCallbacks)
            val values = op.values.toMap()
            op.values.clear()
            op.result.success(mapOf("schema" to 1, "fromMs" to op.start.toEpochMilli(),
                "toMs" to op.end.toEpochMilli(), "metrics" to values))
            return
        }
        val key = op.keys[index]
        if (!hasPermission(key)) {
            op.values[key] = mapOf("status" to "permission_required")
            next(op, index + 1)
            return
        }
        try {
            when (key) {
                "steps" -> {
                    val request = AggregateRecordsRequest.Builder<Long>(range(op))
                        .addAggregationType(StepsRecord.STEPS_COUNT_TOTAL).build()
                    manager!!.aggregate(request, activity.mainExecutor,
                        object : OutcomeReceiver<AggregateRecordsResponse<Long>, HealthConnectException> {
                            override fun onResult(value: AggregateRecordsResponse<Long>) = accept(op) {
                                val count = value.get(StepsRecord.STEPS_COUNT_TOTAL)
                                val sources = if (count == null) emptyList() else
                                    value.getDataOrigins(StepsRecord.STEPS_COUNT_TOTAL)
                                        .map { it.packageName }.sorted()
                                op.values[key] = if (count == null) mapOf("status" to "no_data") else mapOf(
                                    "status" to "data", "value" to count,
                                    "sources" to sources.take(32), "partial" to (sources.size > 32))
                                next(op, index + 1)
                            }
                            override fun onError(error: HealthConnectException) { fail(op) }
                        })
                }
                "heart_rate" -> {
                    val request = ReadRecordsRequestUsingFilters.Builder(HeartRateRecord::class.java)
                        .setTimeRangeFilter(range(op)).setPageSize(50).setAscending(false).build()
                    manager!!.readRecords(request, activity.mainExecutor,
                        object : OutcomeReceiver<ReadRecordsResponse<HeartRateRecord>, HealthConnectException> {
                            override fun onResult(value: ReadRecordsResponse<HeartRateRecord>) = accept(op) {
                                var latest: HeartRateRecord.HeartRateSample? = null
                                var source: Metadata? = null
                                var inspected = 0
                                var partial = value.nextPageToken != -1L
                                for (record in value.records.take(50)) {
                                    for (sample in record.samples.asReversed()) {
                                        if (++inspected > 5000) { partial = true; break }
                                        if (sample.time.isBefore(op.start) || sample.time.isAfter(op.end)) continue
                                        if (latest == null || sample.time.isAfter(latest.time)) {
                                            latest = sample; source = record.metadata
                                        }
                                    }
                                    if (inspected > 5000) break
                                }
                                op.values[key] = if (latest == null || source == null) mapOf("status" to "no_data") else mapOf(
                                    "status" to "data", "value" to latest.beatsPerMinute,
                                    "atMs" to latest.time.toEpochMilli(),
                                    "sources" to listOf(source.dataOrigin.packageName),
                                    "recording" to recording(source), "partial" to partial)
                                next(op, index + 1)
                            }
                            override fun onError(error: HealthConnectException) { fail(op) }
                        })
                }
                "sleep" -> {
                    val request = ReadRecordsRequestUsingFilters.Builder(SleepSessionRecord::class.java)
                        .setTimeRangeFilter(range(op)).setPageSize(50).setAscending(false).build()
                    manager!!.readRecords(request, activity.mainExecutor,
                        object : OutcomeReceiver<ReadRecordsResponse<SleepSessionRecord>, HealthConnectException> {
                            override fun onResult(value: ReadRecordsResponse<SleepSessionRecord>) = accept(op) {
                                // Session boundaries are not a measurement of time asleep.
                                // The SDK returns records; do not access/export their titles, notes or stages.
                                val record = value.records.take(50).filter {
                                    !it.startTime.isBefore(op.start) && !it.endTime.isAfter(op.end)
                                }.maxByOrNull { it.endTime }
                                op.values[key] = if (record == null) mapOf("status" to "no_data") else mapOf(
                                    "status" to "data", "startMs" to record.startTime.toEpochMilli(),
                                    "endMs" to record.endTime.toEpochMilli(),
                                    "sources" to listOf(record.metadata.dataOrigin.packageName),
                                    "recording" to recording(record.metadata),
                                    "partial" to (value.nextPageToken != -1L))
                                next(op, index + 1)
                            }
                            override fun onError(error: HealthConnectException) { fail(op) }
                        })
                }
            }
        } catch (_: Exception) { fail(op) }
    }

    private fun recording(meta: Metadata): String = when (meta.recordingMethod) {
        Metadata.RECORDING_METHOD_MANUAL_ENTRY -> "manual"
        Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED -> "automatic"
        Metadata.RECORDING_METHOD_ACTIVELY_RECORDED -> "active"
        else -> "unknown"
    }

    private fun fail(op: ReadOperation) {
        if (active !== op) return
        active = null
        op.values.clear()
        op.timeout?.let(handler::removeCallbacks)
        // Never forward SDK exception strings, record IDs or health payloads.
        op.result.error("read_failed", "Health data could not be read. Check permissions and try manually.", null)
    }

    private fun cancelRead() {
        val op = active ?: return
        active = null
        op.values.clear()
        op.timeout?.let(handler::removeCallbacks)
        op.result.error("cancelled", "The foreground read was cancelled.", null)
    }

    override fun onResume() { foreground = true }
    override fun onPause() { foreground = false; cancelRead() }
    override fun onPermissionsResult(code: Int): Boolean {
        if (code != PERMISSION_REQUEST) return false
        val pending = pendingPermission
        pendingPermission = null
        permissionTimeout?.let(handler::removeCallbacks)
        permissionTimeout = null
        // A grant never starts a read. Flutter requires a new explicit action.
        pending?.success(permissions.keys.filter { hasPermission(it) })
        return true
    }
    override fun dispose() {
        foreground = false
        disposed = true
        cancelRead()
        pendingPermission?.error("cancelled", "The permission request owner was closed.", null)
        pendingPermission = null
        permissionTimeout?.let(handler::removeCallbacks)
        permissionTimeout = null
    }
}
