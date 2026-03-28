package com.fit_up.health.capacitor

import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.activity.result.ActivityResultCallback
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.aggregate.AggregationResultGroupedByPeriod
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseRouteResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.BodyTemperatureRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDateTime
import java.time.Period
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Optional
import java.util.concurrent.atomic.AtomicReference
import kotlin.jvm.optionals.getOrDefault

enum class CapHealthPermission {
    READ_STEPS, READ_WORKOUTS, READ_HEART_RATE, READ_ROUTE, READ_ACTIVE_CALORIES, READ_TOTAL_CALORIES, READ_DISTANCE, READ_SLEEP, READ_HEIGHT, READ_WEIGHT, READ_BODY_TEMPERATURE;

    companion object {
        fun from(s: String): CapHealthPermission? {
            return try {
                CapHealthPermission.valueOf(s)
            } catch (e: Exception) {
                null
            }
        }
    }
}


@CapacitorPlugin(
    name = "HealthPlugin",
    permissions = [
        Permission(
            alias = "READ_STEPS",
            strings = ["android.permission.health.READ_STEPS"]
        ),
        Permission(
            alias = "READ_WORKOUTS",
            strings = ["android.permission.health.READ_EXERCISE"]
        ),
        Permission(
            alias = "READ_DISTANCE",
            strings = ["android.permission.health.READ_DISTANCE"]
        ),
        Permission(
            alias = "READ_ACTIVE_CALORIES",
            strings = ["android.permission.health.READ_ACTIVE_CALORIES_BURNED"]
        ),
        Permission(
            alias = "READ_TOTAL_CALORIES",
            strings = ["android.permission.health.READ_TOTAL_CALORIES_BURNED"]
        ),
        Permission(
            alias = "READ_HEART_RATE",
            strings = ["android.permission.health.READ_HEART_RATE"]
        ),
        Permission(
            alias = "READ_ROUTE",
            strings = ["android.permission.health.READ_EXERCISE_ROUTE"]
        ),
        Permission(
            alias = "READ_SLEEP",
            strings = ["android.permission.health.READ_SLEEP"]
        ),
        Permission(
            alias = "READ_HEIGHT",
            strings = ["android.permission.health.READ_HEIGHT"]
        ),
        Permission(
            alias = "READ_WEIGHT",
            strings = ["android.permission.health.READ_WEIGHT"]
        ),
        Permission(
            alias = "READ_BODY_TEMPERATURE",
            strings = ["android.permission.health.READ_BODY_TEMPERATURE"]
        )
    ]
)
class HealthPlugin : Plugin() {


    private val tag = "CapHealth"

    private lateinit var healthConnectClient: HealthConnectClient
    private var available: Boolean = false

    private lateinit var permissionsLauncher: ActivityResultLauncher<Set<String>>
    override fun load() {
        super.load()

        val contract: ActivityResultContract<Set<String>, Set<String>> =
            PermissionController.createRequestPermissionResultContract()

        val callback: ActivityResultCallback<Set<String>> = ActivityResultCallback { grantedPermissions ->
            val context = requestPermissionContext.get()
            if (context != null) {
                val result = grantedPermissionResult(context.requestedPermissions, grantedPermissions)
                context.pluginCal.resolve(result)
            }
        }
        permissionsLauncher = activity.registerForActivityResult(contract, callback)
    }

    // Check if Google Health Connect is available. Must be called before anything else
    @PluginMethod
    fun isHealthAvailable(call: PluginCall) {

        if (!available) {
            try {
                healthConnectClient = HealthConnectClient.getOrCreate(context)
                available = true
            } catch (e: Exception) {
                Log.e("CAP-HEALTH", "error health connect client", e)
                available = false
            }
        }


        val result = JSObject()
        result.put("available", available)
        call.resolve(result)
    }


    private val permissionMapping = mapOf(
        Pair(CapHealthPermission.READ_WORKOUTS, "android.permission.health.READ_EXERCISE"),
        Pair(CapHealthPermission.READ_ROUTE, "android.permission.health.READ_EXERCISE_ROUTE"),
        Pair(CapHealthPermission.READ_HEART_RATE, "android.permission.health.READ_HEART_RATE"),
        Pair(CapHealthPermission.READ_ACTIVE_CALORIES, "android.permission.health.READ_ACTIVE_CALORIES_BURNED"),
        Pair(CapHealthPermission.READ_TOTAL_CALORIES, "android.permission.health.READ_TOTAL_CALORIES_BURNED"),
        Pair(CapHealthPermission.READ_DISTANCE, "android.permission.health.READ_DISTANCE"),
        Pair(CapHealthPermission.READ_STEPS, "android.permission.health.READ_STEPS"),
        Pair(CapHealthPermission.READ_SLEEP, "android.permission.health.READ_SLEEP"),
        Pair(CapHealthPermission.READ_HEIGHT, "android.permission.health.READ_HEIGHT"),
        Pair(CapHealthPermission.READ_WEIGHT, "android.permission.health.READ_WEIGHT")
    )

    // Check if a set of permissions are granted
    @PluginMethod
    fun checkHealthPermissions(call: PluginCall) {
        val permissionsToCheck = call.getArray("permissions")
        if (permissionsToCheck == null) {
            call.reject("Must provide permissions to check")
            return
        }


        val permissions =
            permissionsToCheck.toList<String>().mapNotNull { CapHealthPermission.from(it) }.toSet()


        CoroutineScope(Dispatchers.IO).launch {
            try {

                val grantedPermissions = healthConnectClient.permissionController.getGrantedPermissions()
                val result = grantedPermissionResult(permissions, grantedPermissions)

                call.resolve(result)
            } catch (e: Exception) {
                call.reject("Checking permissions failed: ${e.message}")
            }
        }
    }

    private fun grantedPermissionResult(requestPermissions: Set<CapHealthPermission>, grantedPermissions: Set<String>): JSObject {
        val readPermissions = JSObject()
        val grantedPermissionsWithoutPrefix = grantedPermissions.map { it.substringAfterLast('.') }
        for (permission in requestPermissions) {

            readPermissions.put(
                permission.name,
                grantedPermissionsWithoutPrefix.contains(permissionMapping[permission]?.substringAfterLast('.'))
            )
        }

        val result = JSObject()
        result.put("permissions", readPermissions)
        return result

    }

    data class RequestPermissionContext(val requestedPermissions: Set<CapHealthPermission>, val pluginCal: PluginCall)

    private val requestPermissionContext = AtomicReference<RequestPermissionContext>()

    // Request a set of permissions from the user
    @PluginMethod
    fun requestHealthPermissions(call: PluginCall) {
        val permissionsToRequest = call.getArray("permissions")
        if (permissionsToRequest == null) {
            call.reject("Must provide permissions to request")
            return
        }

        val permissions = permissionsToRequest.toList<String>().mapNotNull { CapHealthPermission.from(it) }.toSet()
        val healthConnectPermissions = permissions.mapNotNull { permissionMapping[it] }.toSet()


        CoroutineScope(Dispatchers.IO).launch {
            try {
                requestPermissionContext.set(RequestPermissionContext(permissions, call))
                permissionsLauncher.launch(healthConnectPermissions)
            } catch (e: Exception) {
                call.reject("Permission request failed: ${e.message}")
                requestPermissionContext.set(null)
            }
        }
    }

    // Open Google Health Connect app settings
    @PluginMethod
    fun openHealthConnectSettings(call: PluginCall) {
        try {
            val intent = Intent().apply {
                action = HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS
            }
            context.startActivity(intent)
            call.resolve()
        } catch(e: Exception) {
            call.reject(e.message)
        }
    }

    // Open the Google Play Store to install Health Connect
    @PluginMethod
    fun showHealthConnectInPlayStore(call: PluginCall) {
        val uri =
            Uri.parse("https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata")
        val intent = Intent(Intent.ACTION_VIEW, uri)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        call.resolve()
    }

    private fun getMetricAndMapper(dataType: String): MetricAndMapper {
        return when (dataType) {
            "steps" -> metricAndMapper("steps", CapHealthPermission.READ_STEPS, StepsRecord.COUNT_TOTAL) { it?.toDouble() }
            "active-calories" -> metricAndMapper(
                "calories",
                CapHealthPermission.READ_ACTIVE_CALORIES,
                ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL
            ) { it?.inKilocalories }
            "total-calories" -> metricAndMapper(
                "calories",
                CapHealthPermission.READ_TOTAL_CALORIES,
                TotalCaloriesBurnedRecord.ENERGY_TOTAL
            ) { it?.inKilocalories }
            "distance" -> metricAndMapper("distance", CapHealthPermission.READ_DISTANCE, DistanceRecord.DISTANCE_TOTAL) { it?.inMeters }
            else -> throw RuntimeException("Unsupported dataType: $dataType")
        }
    }

    @PluginMethod
    fun queryAggregated(call: PluginCall) {
        try {
            val startDate = call.getString("startDate")
            val endDate = call.getString("endDate")
            val dataType = call.getString("dataType")
            val bucket = call.getString("bucket")

            if (startDate == null || endDate == null || dataType == null || bucket == null) {
                call.reject("Missing required parameters: startDate, endDate, dataType, or bucket")
                return
            }

            val startDateTime = Instant.parse(startDate).atZone(ZoneId.systemDefault()).toLocalDateTime()
            val endDateTime = Instant.parse(endDate).atZone(ZoneId.systemDefault()).toLocalDateTime()

            val metricAndMapper = getMetricAndMapper(dataType)

            val period = when (bucket) {
                "day" -> Period.ofDays(1)
                else -> throw RuntimeException("Unsupported bucket: $bucket")
            }


            CoroutineScope(Dispatchers.IO).launch {
                try {

                    val r = queryAggregatedMetric(metricAndMapper, TimeRangeFilter.between(startDateTime, endDateTime), period)

                    val aggregatedList = JSArray()
                    r.forEach { aggregatedList.put(it.toJs()) }

                    val finalResult = JSObject()
                    finalResult.put("aggregatedData", aggregatedList)
                    call.resolve(finalResult)

                } catch (e: Exception) {
                    call.reject("Error querying aggregated data: ${e.message}")
                }
            }
        } catch (e: Exception) {
            call.reject(e.message)
            return
        }
    }


    private fun <M : Any> metricAndMapper(
        name: String,
        permission: CapHealthPermission,
        metric: AggregateMetric<M>,
        mapper: (M?) -> Double?
    ): MetricAndMapper {
        @Suppress("UNCHECKED_CAST")
        return MetricAndMapper(name, permission, metric, mapper as (Any?) -> Double?)
    }

    data class MetricAndMapper(
        val name: String,
        val permission: CapHealthPermission,
        val metric: AggregateMetric<Any>,
        val mapper: (Any?) -> Double?
    ) {
        fun getValue(a: AggregationResult): Double? {
            return mapper(a[metric])
        }
    }

    data class AggregatedSample(val startDate: LocalDateTime, val endDate: LocalDateTime, val value: Double?) {
        fun toJs(): JSObject {
            val o = JSObject()
            o.put("startDate", startDate)
            o.put("endDate", endDate)
            o.put("value", value)

            return o

        }
    }

    private suspend fun queryAggregatedMetric(
        metricAndMapper: MetricAndMapper, timeRange: TimeRangeFilter, period: Period,
    ): List<AggregatedSample> {
        if (!hasPermission(metricAndMapper.permission)) {
            return emptyList()
        }

        val response: List<AggregationResultGroupedByPeriod> = healthConnectClient.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(
                metrics = setOf(metricAndMapper.metric),
                timeRangeFilter = timeRange,
                timeRangeSlicer = period
            )
        )

        return response.map {
            val mappedValue = metricAndMapper.getValue(it.result)
            AggregatedSample(it.startTime, it.endTime, mappedValue)
        }

    }

    private suspend fun hasPermission(p: CapHealthPermission): Boolean {
        return healthConnectClient.permissionController.getGrantedPermissions().map { it.substringAfterLast('.') }.toSet()
            .contains(permissionMapping[p]?.substringAfterLast('.'))
    }


    @PluginMethod
    fun queryWorkouts(call: PluginCall) {
        val startDate = call.getString("startDate")
        val endDate = call.getString("endDate")
        val includeHeartRate: Boolean = call.getBoolean("includeHeartRate", false) == true
        val includeRoute: Boolean = call.getBoolean("includeRoute", false) == true
        val includeSteps: Boolean = call.getBoolean("includeSteps", false) == true
        if (startDate == null || endDate == null) {
            call.reject("Missing required parameters: startDate or endDate")
            return
        }

        val startDateTime = Instant.parse(startDate).atZone(ZoneId.systemDefault()).toLocalDateTime()
        val endDateTime = Instant.parse(endDate).atZone(ZoneId.systemDefault()).toLocalDateTime()

        val timeRange = TimeRangeFilter.between(startDateTime, endDateTime)
        val request =
            ReadRecordsRequest(ExerciseSessionRecord::class, timeRange, emptySet(), true, 1000)

        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Query workouts (exercise sessions)
                val response = healthConnectClient.readRecords(request)

                val workoutsArray = JSArray()

                for (workout in response.records) {
                    val workoutObject = JSObject()
                    workoutObject.put("id", workout.metadata.id)
                    workoutObject.put(
                        "sourceName",
                        Optional.ofNullable(workout.metadata.device?.model).getOrDefault("") +
                                Optional.ofNullable(workout.metadata.device?.model).getOrDefault("")
                    )
                    workoutObject.put("sourceBundleId", workout.metadata.dataOrigin.packageName)
                    workoutObject.put("startDate", workout.startTime.toString())
                    workoutObject.put("endDate", workout.endTime.toString())
                    workoutObject.put("workoutType", exerciseTypeMapping.getOrDefault(workout.exerciseType, "OTHER"))
                    workoutObject.put("title", workout.title)
                    val duration = if (workout.segments.isEmpty()) {
                        workout.endTime.epochSecond - workout.startTime.epochSecond
                    } else {
                        workout.segments.map { it.endTime.epochSecond - it.startTime.epochSecond }
                            .stream().mapToLong { it }.sum()
                    }
                    workoutObject.put("duration", duration)

                    if (includeSteps) {
                        addWorkoutMetric(workout, workoutObject, getMetricAndMapper("steps"))
                    }

                    val readTotalCaloriesResult = addWorkoutMetric(workout, workoutObject, getMetricAndMapper("total-calories"))
                    if(!readTotalCaloriesResult) {
                        addWorkoutMetric(workout, workoutObject, getMetricAndMapper("active-calories"))
                    }

                    addWorkoutMetric(workout, workoutObject, getMetricAndMapper("distance"))

                    if (includeHeartRate && hasPermission(CapHealthPermission.READ_HEART_RATE)) {
                        // Query and add heart rate data if requested
                        val heartRates =
                            queryHeartRateForWorkout(workout.startTime, workout.endTime)
                        workoutObject.put("heartRate", heartRates)
                    }

                    if (includeRoute && workout.exerciseRouteResult is ExerciseRouteResult.Data) {
                        val route =
                            queryRouteForWorkout(workout.exerciseRouteResult as ExerciseRouteResult.Data)
                        workoutObject.put("route", route)
                    }

                    workoutsArray.put(workoutObject)
                }

                val result = JSObject()
                result.put("workouts", workoutsArray)
                call.resolve(result)

            } catch (e: Exception) {
                call.reject("Error querying workouts: ${e.message}")
            }
        }
    }

    private suspend fun addWorkoutMetric(
        workout: ExerciseSessionRecord,
        jsWorkout: JSObject,
        metricAndMapper: MetricAndMapper,
    ): Boolean {

        if (hasPermission(metricAndMapper.permission)) {
            try {
                val request = AggregateRequest(
                    setOf(metricAndMapper.metric),
                    TimeRangeFilter.Companion.between(workout.startTime, workout.endTime),
                    emptySet()
                )
                val aggregation = healthConnectClient.aggregate(request)
                val value = metricAndMapper.getValue(aggregation)
                if(value != null) {
                    jsWorkout.put(metricAndMapper.name, value)
                    return true
                }
            } catch (e: Exception) {
                Log.e(tag, "Error", e)
            }
        }
        return false;
    }


    private suspend fun queryHeartRateForWorkout(startTime: Instant, endTime: Instant): JSArray {
        val request =
            ReadRecordsRequest(HeartRateRecord::class, TimeRangeFilter.between(startTime, endTime))
        val heartRateRecords = healthConnectClient.readRecords(request)

        val heartRateArray = JSArray()
        val samples = heartRateRecords.records.flatMap { it.samples }
        for (sample in samples) {
            val heartRateObject = JSObject()
            heartRateObject.put("timestamp", sample.time.toString())
            heartRateObject.put("bpm", sample.beatsPerMinute)
            heartRateArray.put(heartRateObject)
        }
        return heartRateArray
    }

    private fun queryRouteForWorkout(routeResult: ExerciseRouteResult.Data): JSArray {

        val routeArray = JSArray()
        for (record in routeResult.exerciseRoute.route) {
            val routeObject = JSObject()
            routeObject.put("timestamp", record.time.toString())
            routeObject.put("lat", record.latitude)
            routeObject.put("lng", record.longitude)
            routeObject.put("alt", record.altitude)
            routeArray.put(routeObject)
        }
        return routeArray
    }
    
    @PluginMethod
    fun querySleepData(call: PluginCall) {
        val startDate = call.getString("startDate")
        val endDate = call.getString("endDate")
        
        if (startDate == null || endDate == null) {
            call.reject("Missing required parameters: startDate or endDate")
            return
        }
        
        val startDateTime = Instant.parse(startDate).atZone(ZoneId.systemDefault()).toLocalDateTime()
        val endDateTime = Instant.parse(endDate).atZone(ZoneId.systemDefault()).toLocalDateTime()
        
        val timeRange = TimeRangeFilter.between(startDateTime, endDateTime)
        val request = ReadRecordsRequest(SleepSessionRecord::class, timeRange, emptySet(), true, 1000)
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                if (!hasPermission(CapHealthPermission.READ_SLEEP)) {
                    call.reject("Sleep permission not granted")
                    return@launch
                }
                
                // Query sleep sessions
                val response = healthConnectClient.readRecords(request)
                
                val sleepArray = JSArray()
                
                for (sleepSession in response.records) {
                    val sleepObject = JSObject()
                    sleepObject.put("id", sleepSession.metadata.id)
                    sleepObject.put(
                        "sourceName",
                        Optional.ofNullable(sleepSession.metadata.device?.model).getOrDefault("") +
                                Optional.ofNullable(sleepSession.metadata.device?.model).getOrDefault("")
                    )
                    sleepObject.put("sourceBundleId", sleepSession.metadata.dataOrigin.packageName)
                    sleepObject.put("startDate", sleepSession.startTime.toString())
                    sleepObject.put("endDate", sleepSession.endTime.toString())
                    sleepObject.put("title", sleepSession.title)
                    
                    // Calculate total duration in seconds
                    val duration = sleepSession.endTime.epochSecond - sleepSession.startTime.epochSecond
                    sleepObject.put("duration", duration)
                    
                    // Process sleep stages if available
                    if (sleepSession.stages.isNotEmpty()) {
                        val stagesArray = JSArray()
                        
                        for (stage in sleepSession.stages) {
                            val stageObject = JSObject()
                            stageObject.put("startDate", stage.startTime.toString())
                            stageObject.put("endDate", stage.endTime.toString())
                            stageObject.put("stage", sleepStageMapping.getOrDefault(stage.stage, "UNKNOWN"))
                            
                            // Calculate stage duration in seconds
                            val stageDuration = stage.endTime.epochSecond - stage.startTime.epochSecond
                            stageObject.put("duration", stageDuration)
                            
                            stagesArray.put(stageObject)
                        }
                        
                        sleepObject.put("stages", stagesArray)
                    }
                    
                    // Calculate sleep metrics
                    if (sleepSession.stages.isNotEmpty()) {
                        // Time in bed = total sleep session duration
                        sleepObject.put("timeInBed", duration)
                        
                        // Calculate actual sleep time (excluding AWAKE and OUT_OF_BED stages)
                        val sleepTime = sleepSession.stages
                            .filter { it.stage != 1 && it.stage != 3 } // Filter out AWAKE and OUT_OF_BED
                            .sumOf { it.endTime.epochSecond - it.startTime.epochSecond }
                        sleepObject.put("sleepTime", sleepTime)
                        
                        // Deep sleep time
                        val deepSleepTime = sleepSession.stages
                            .filter { it.stage == 5 } // DEEP sleep
                            .sumOf { it.endTime.epochSecond - it.startTime.epochSecond }
                        sleepObject.put("deepSleepTime", deepSleepTime)
                        
                        // REM sleep time
                        val remSleepTime = sleepSession.stages
                            .filter { it.stage == 6 } // REM sleep
                            .sumOf { it.endTime.epochSecond - it.startTime.epochSecond }
                        sleepObject.put("remSleepTime", remSleepTime)
                        
                        // Light sleep time
                        val lightSleepTime = sleepSession.stages
                            .filter { it.stage == 4 } // LIGHT sleep
                            .sumOf { it.endTime.epochSecond - it.startTime.epochSecond }
                        sleepObject.put("lightSleepTime", lightSleepTime)
                        
                        // Awake time during sleep session
                        val awakeTime = sleepSession.stages
                            .filter { it.stage == 1 } // AWAKE
                            .sumOf { it.endTime.epochSecond - it.startTime.epochSecond }
                        sleepObject.put("awakeTime", awakeTime)
                    }
                    
                    sleepArray.put(sleepObject)
                }
                
                val result = JSObject()
                result.put("sleepSessions", sleepArray)
                call.resolve(result)
                
            } catch (e: Exception) {
                call.reject("Error querying sleep data: ${e.message}")
            }
        }
    }


    private val exerciseTypeMapping = mapOf(
        0 to "OTHER",
        2 to "BADMINTON",
        4 to "BASEBALL",
        5 to "BASKETBALL",
        8 to "BIKING",
        9 to "BIKING_STATIONARY",
        10 to "BOOT_CAMP",
        11 to "BOXING",
        13 to "CALISTHENICS",
        14 to "CRICKET",
        16 to "DANCING",
        25 to "ELLIPTICAL",
        26 to "EXERCISE_CLASS",
        27 to "FENCING",
        28 to "FOOTBALL_AMERICAN",
        29 to "FOOTBALL_AUSTRALIAN",
        31 to "FRISBEE_DISC",
        32 to "GOLF",
        33 to "GUIDED_BREATHING",
        34 to "GYMNASTICS",
        35 to "HANDBALL",
        36 to "HIGH_INTENSITY_INTERVAL_TRAINING",
        37 to "HIKING",
        38 to "ICE_HOCKEY",
        39 to "ICE_SKATING",
        44 to "MARTIAL_ARTS",
        46 to "PADDLING",
        47 to "PARAGLIDING",
        48 to "PILATES",
        50 to "RACQUETBALL",
        51 to "ROCK_CLIMBING",
        52 to "ROLLER_HOCKEY",
        53 to "ROWING",
        54 to "ROWING_MACHINE",
        55 to "RUGBY",
        56 to "RUNNING",
        57 to "RUNNING_TREADMILL",
        58 to "SAILING",
        59 to "SCUBA_DIVING",
        60 to "SKATING",
        61 to "SKIING",
        62 to "SNOWBOARDING",
        63 to "SNOWSHOEING",
        64 to "SOCCER",
        65 to "SOFTBALL",
        66 to "SQUASH",
        68 to "STAIR_CLIMBING",
        69 to "STAIR_CLIMBING_MACHINE",
        70 to "STRENGTH_TRAINING",
        71 to "STRETCHING",
        72 to "SURFING",
        73 to "SWIMMING_OPEN_WATER",
        74 to "SWIMMING_POOL",
        75 to "TABLE_TENNIS",
        76 to "TENNIS",
        78 to "VOLLEYBALL",
        79 to "WALKING",
        80 to "WATER_POLO",
        81 to "WEIGHTLIFTING",
        82 to "WHEELCHAIR",
        83 to "YOGA"
    )
    
    // Sleep stage mapping based on Health Connect's SleepSessionRecord.Stage constants
    private val sleepStageMapping = mapOf(
        0 to "UNKNOWN",
        1 to "AWAKE",
        2 to "SLEEPING",
        3 to "OUT_OF_BED",
        4 to "LIGHT",
        5 to "DEEP",
        6 to "REM"
    )
    
    @PluginMethod
    fun queryHeight(call: PluginCall) {
        try {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    if (!hasPermission(CapHealthPermission.READ_HEIGHT)) {
                        call.reject("Height permission not granted")
                        return@launch
                    }
                    
                    // Create a request to read height records
                    val request = ReadRecordsRequest(
                        recordType = HeightRecord::class,
                        timeRangeFilter = TimeRangeFilter.between(Instant.EPOCH, Instant.now()),
                        ascendingOrder = false,
                        pageSize = 1
                    )
                    
                    val response = healthConnectClient.readRecords(request)
                    
                    if (response.records.isEmpty()) {
                        call.resolve(JSObject().apply {
                            put("height", null)
                            put("timestamp", null)
                        })
                        return@launch
                    }
                    
                    val heightRecord = response.records.first()
                    val result = JSObject().apply {
                        put("height", heightRecord.height.inMeters)
                        put("timestamp", heightRecord.time.toString())
                        put("metadata", JSObject().apply {
                            put("id", heightRecord.metadata.id)
                            put("lastModifiedTime", heightRecord.metadata.lastModifiedTime.toString())
                            put("clientRecordId", heightRecord.metadata.clientRecordId ?: "")
                            put("dataOrigin", heightRecord.metadata.dataOrigin.packageName)
                        })
                    }
                    
                    call.resolve(result)
                    
                } catch (e: Exception) {
                    call.reject("Error reading height data: ${e.message}")
                }
            }
        } catch (e: Exception) {
            call.reject(e.message)
        }
    }
    
    @PluginMethod
    fun queryWeight(call: PluginCall) {
        try {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    if (!hasPermission(CapHealthPermission.READ_WEIGHT)) {
                        call.reject("Weight permission not granted")
                        return@launch
                    }
                    
                    // Create a request to read weight records
                    val request = ReadRecordsRequest(
                        recordType = WeightRecord::class,
                        timeRangeFilter = TimeRangeFilter.between(Instant.EPOCH, Instant.now()),
                        ascendingOrder = false,
                        pageSize = 1
                    )
                    
                    val response = healthConnectClient.readRecords(request)
                    
                    if (response.records.isEmpty()) {
                        call.resolve(JSObject().apply {
                            put("weight", null)
                            put("timestamp", null)
                        })
                        return@launch
                    }
                    
                    val weightRecord = response.records.first()
                    val result = JSObject().apply {
                        put("weight", weightRecord.weight.inKilograms)
                        put("timestamp", weightRecord.time.toString())
                        put("metadata", JSObject().apply {
                            put("id", weightRecord.metadata.id)
                            put("lastModifiedTime", weightRecord.metadata.lastModifiedTime.toString())
                            put("clientRecordId", weightRecord.metadata.clientRecordId ?: "")
                            put("dataOrigin", weightRecord.metadata.dataOrigin.packageName)
                        })
                    }
                    
                    call.resolve(result)
                    
                } catch (e: Exception) {
                    call.reject("Error reading weight data: ${e.message}")
                }
            }
        } catch (e: Exception) {
            call.reject(e.message)
        }
    }
    
    @PluginMethod
    fun queryHeartRate(call: PluginCall) {
        val startDate = call.getString("startDate")
        val endDate = call.getString("endDate")
        if (startDate == null || endDate == null) {
            call.reject("Missing required parameters: startDate or endDate")
            return
        }

        try {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    if (!hasPermission(CapHealthPermission.READ_HEART_RATE)) {
                        call.reject("Heart rate permission not granted")
                        return@launch
                    }

                    val startInstant = Instant.parse(startDate)
                    val endInstant = Instant.parse(endDate)

                    val request = ReadRecordsRequest(
                        HeartRateRecord::class,
                        TimeRangeFilter.between(startInstant, endInstant)
                    )
                    val heartRateRecords = healthConnectClient.readRecords(request)

                    val heartRateArray = JSArray()
                    val samples = heartRateRecords.records.flatMap { it.samples }
                    for (sample in samples) {
                        val heartRateObject = JSObject()
                        heartRateObject.put("timestamp", sample.time.toString())
                        heartRateObject.put("bpm", sample.beatsPerMinute)
                        heartRateArray.put(heartRateObject)
                    }

                    val result = JSObject()
                    result.put("heartRateSamples", heartRateArray)
                    call.resolve(result)

                } catch (e: Exception) {
                    call.reject("Error reading heart rate data: ${e.message}")
                }
            }
        } catch (e: Exception) {
            call.reject(e.message)
        }
    }

    @PluginMethod
    fun queryBodyTemperature(call: PluginCall) {
        try {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    if (!hasPermission(CapHealthPermission.READ_BODY_TEMPERATURE)) {
                        call.reject("Body temperature permission not granted")
                        return@launch
                    }
                    
                    // Create a request to read body temperature records
                    val request = ReadRecordsRequest(
                        recordType = BodyTemperatureRecord::class,
                        timeRangeFilter = TimeRangeFilter.between(Instant.EPOCH, Instant.now()),
                        ascendingOrder = false,
                        pageSize = 1
                    )
                    
                    val response = healthConnectClient.readRecords(request)
                    
                    if (response.records.isEmpty()) {
                        call.resolve(JSObject().apply {
                            put("temperature", null)
                            put("timestamp", null)
                        })
                        return@launch
                    }
                    
                    val temperatureRecord = response.records.first()
                    val result = JSObject().apply {
                        put("temperature", temperatureRecord.temperature.inCelsius)
                        put("timestamp", temperatureRecord.time.toString())
                        put("metadata", JSObject().apply {
                            put("id", temperatureRecord.metadata.id)
                            put("lastModifiedTime", temperatureRecord.metadata.lastModifiedTime.toString())
                            put("clientRecordId", temperatureRecord.metadata.clientRecordId ?: "")
                            put("dataOrigin", temperatureRecord.metadata.dataOrigin.packageName)
                        })
                    }
                    
                    call.resolve(result)
                    
                } catch (e: Exception) {
                    call.reject("Error reading temperature data: ${e.message}")
                }
            }
        } catch (e: Exception) {
            call.reject(e.message)
        }
    }

}
