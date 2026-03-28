export interface HealthPlugin {
    /**
     * Checks if health API is available.
     * Android: If false is returned, the Google Health Connect app is probably not installed.
     * See showHealthConnectInPlayStore()
     *
     */
    isHealthAvailable(): Promise<{
        available: boolean;
    }>;
    /**
     * Android only: Returns for each given permission, if it was granted by the underlying health API
     * @param permissions permissions to query
     */
    checkHealthPermissions(permissions: PermissionsRequest): Promise<PermissionResponse>;
    /**
     * Requests the permissions from the user.
     *
     * Android: Apps can ask only a few times for permissions, after that the user has to grant them manually in
     * the Health Connect app. See openHealthConnectSettings()
     *
     * iOS: If the permissions are already granted or denied, this method will just return without asking the user. In iOS
     * we can't really detect if a user granted or denied a permission. The return value reflects the assumption that all
     * permissions were granted.
     *
     * @param permissions permissions to request
     */
    requestHealthPermissions(permissions: PermissionsRequest): Promise<PermissionResponse>;
    /**
     * Opens the apps settings, which is kind of wrong, because health permissions are configured under:
     * Settings > Apps > (Apple) Health > Access and Devices > [app-name]
     * But we can't go there directly.
     */
    openAppleHealthSettings(): Promise<void>;
    /**
     * Opens the Google Health Connect app
     */
    openHealthConnectSettings(): Promise<void>;
    /**
     * Opens the Google Health Connect app in PlayStore
     */
    showHealthConnectInPlayStore(): Promise<void>;
    /**
     * Query aggregated data
     * @param request
     */
    queryAggregated(request: QueryAggregatedRequest): Promise<QueryAggregatedResponse>;
    /**
     * Query workouts
     * @param request
     */
    queryWorkouts(request: QueryWorkoutRequest): Promise<QueryWorkoutResponse>;
    /**
     * Query sleep data
     * @param request
     */
    querySleepData(request: QuerySleepRequest): Promise<QuerySleepResponse>;
    /**
     * Query height data
     */
    queryHeight(): Promise<HeightData>;
    /**
     * Query weight data
     */
    queryWeight(): Promise<WeightData>;
    /**
     * Query body temperature data
     * @returns Body temperature data
     * @since 0.0.1
     */
    queryBodyTemperature(): Promise<BodyTemperatureData>;
    /**
     * Query heart rate data directly (not tied to a workout)
     * @param request date range to query
     */
    queryHeartRate(request: QueryHeartRateRequest): Promise<QueryHeartRateResponse>;
}
export declare type HealthPermission = 'READ_STEPS' | 'READ_WORKOUTS' | 'READ_ACTIVE_CALORIES' | 'READ_TOTAL_CALORIES' | 'READ_DISTANCE' | 'READ_HEART_RATE' | 'READ_ROUTE' | 'READ_MINDFULNESS' | 'READ_SLEEP' | 'READ_BODY_TEMPERATURE' | 'READ_HEIGHT' | 'READ_WEIGHT';
export interface PermissionsRequest {
    permissions: HealthPermission[];
}
export interface PermissionResponse {
    permissions: {
        [key: string]: boolean;
    }[];
}
export interface QueryWorkoutRequest {
    startDate: string;
    endDate: string;
    includeHeartRate: boolean;
    includeRoute: boolean;
    includeSteps: boolean;
}
export interface HeartRateSample {
    timestamp: string;
    bpm: number;
}
export interface RouteSample {
    timestamp: string;
    lat: number;
    lng: number;
    alt?: number;
}
export interface QueryWorkoutResponse {
    workouts: Workout[];
}
export interface Workout {
    startDate: string;
    endDate: string;
    workoutType: string;
    sourceName: string;
    id?: string;
    duration: number;
    distance?: number;
    steps?: number;
    calories: number;
    sourceBundleId: string;
    route?: RouteSample[];
    heartRate?: HeartRateSample[];
}
export interface QueryAggregatedRequest {
    startDate: string;
    endDate: string;
    dataType: 'steps' | 'active-calories' | 'mindfulness';
    bucket: string;
}
export interface QueryAggregatedResponse {
    aggregatedData: AggregatedSample[];
}
export interface AggregatedSample {
    startDate: string;
    endDate: string;
    value: number;
}
export interface QuerySleepRequest {
    startDate: string;
    endDate: string;
}
export interface SleepStage {
    startDate: string;
    endDate: string;
    stage: string;
    duration: number;
}
export interface SleepSession {
    id: string;
    startDate: string;
    endDate: string;
    sourceName: string;
    sourceBundleId: string;
    title: string;
    duration: number;
    stages?: SleepStage[];
    timeInBed?: number;
    sleepTime?: number;
    deepSleepTime?: number;
    remSleepTime?: number;
    lightSleepTime?: number;
    awakeTime?: number;
}
export interface QuerySleepResponse {
    sleepSessions: SleepSession[];
}
export interface HeightData {
    height: number | null;
    timestamp: string | null;
    metadata?: {
        id: string;
        lastModifiedTime: string;
        clientRecordId: string;
        dataOrigin: string;
    };
}
export interface WeightData {
    weight: number | null;
    timestamp: string | null;
    metadata?: {
        id: string;
        lastModifiedTime: string;
        clientRecordId: string;
        dataOrigin: string;
    };
}
export interface QueryHeartRateRequest {
    startDate: string;
    endDate: string;
}
export interface QueryHeartRateResponse {
    heartRateSamples: HeartRateSample[];
}
export interface BodyTemperatureData {
    /**
     * Body temperature value in celsius
     */
    temperature: number;
    /**
     * ISO8601 timestamp
     */
    timestamp: string;
    /**
     * Metadata about the measurement
     */
    metadata: {
        id: string;
        lastModifiedTime: string;
        clientRecordId: string;
        dataOrigin: string;
    };
}
