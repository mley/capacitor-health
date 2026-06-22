export interface HealthPlugin {
  /**
   * Checks if health API is available.
   * Android: If false is returned, the Google Health Connect app is probably not installed.
   * See showHealthConnectInPlayStore()
   *
   */
  isHealthAvailable(): Promise<{ available: boolean }>;

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
   * Query individual records for a given data type. Unlike queryAggregated,
   * this returns each record separately with its data origin, which is useful
   * for detecting duplicate sources.
   *
   * Android only. iOS rejects with "not implemented".
   *
   * @param request
   */
  queryRecords(request: QueryRecordsRequest): Promise<QueryRecordsResponse>;

  /**
   * Query sleep sessions.
   *
   * Android: Reads Health Connect `SleepSessionRecord`s. Each session already
   * carries its own stages (awake / light / deep / rem / ...).
   *
   * iOS: HealthKit has no native sleep-session concept, only individual sleep
   * analysis category samples. Contiguous samples from the same source are
   * grouped into a session; samples separated by more than `sessionGapMinutes`
   * (default 60) start a new session. Each underlying sample becomes a stage.
   *
   * Requires the `READ_SLEEP` permission.
   *
   * @param request
   */
  querySleep(request: QuerySleepRequest): Promise<QuerySleepResponse>;
}

export declare type HealthPermission =
  | 'READ_STEPS'
  | 'READ_WORKOUTS'
  | 'READ_ACTIVE_CALORIES'
  | 'READ_TOTAL_CALORIES'
  | 'READ_DISTANCE'
  | 'READ_HEART_RATE'
  | 'READ_ROUTE'
  | 'READ_MINDFULNESS'
  | 'READ_SLEEP';

export interface PermissionsRequest {
  permissions: HealthPermission[];
}

export interface PermissionResponse {
  permissions: { [key: string]: boolean }[];
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
  /**
   * `sleep` returns the total time asleep per bucket (Health Connect's
   * `SLEEP_DURATION_TOTAL`, in seconds, excluding awake stages). **Android only** —
   * iOS rejects it; on iOS use `querySleep` and sum the sessions' `duration`.
   */
  dataType: 'steps' | 'active-calories' | 'mindfulness' | 'sleep';
  bucket: string;
  /**
   * Optional list of package names (Android) or bundle identifiers (iOS) to
   * restrict the aggregation to. When omitted or empty, data from all sources
   * is included.
   *
   * Example: `['com.sec.android.app.shealth']` to only aggregate Samsung
   * Health data.
   */
  dataOrigins?: string[];
}

export interface QueryAggregatedResponse {
  aggregatedData: AggregatedSample[];
}

export interface AggregatedSample {
  startDate: string;
  endDate: string;
  value: number;
}

export interface QueryRecordsRequest {
  startDate: string;
  endDate: string;
  dataType: 'steps';
}

export interface HealthRecord {
  startDate: string;
  endDate: string;
  value: number;
  sourceBundleId: string;
}

export interface QueryRecordsResponse {
  records: HealthRecord[];
}

export interface QuerySleepRequest {
  startDate: string;
  endDate: string;
  /**
   * iOS only: maximum gap, in minutes, between two consecutive sleep samples
   * from the same source for them to be treated as part of the same session.
   * Defaults to 60. Ignored on Android, where Health Connect already groups
   * samples into sessions.
   */
  sessionGapMinutes?: number;
}

export interface QuerySleepResponse {
  sessions: SleepSession[];
}

export interface SleepSession {
  /** Start of the session (start of the first stage). ISO 8601 string. */
  startDate: string;
  /** End of the session (end of the last stage). ISO 8601 string. */
  endDate: string;
  /**
   * Total time asleep in seconds, i.e. the summed duration of the asleep stages
   * (`light` + `deep` + `rem` + `asleep`). Excludes `awake`, `inBed` and
   * `outOfBed` stages, so this is typically less than `endDate - startDate`.
   */
  duration: number;
  /** Identifier of the session. On Android this is the record id. */
  id?: string;
  sourceName: string;
  sourceBundleId: string;
  /** True if the session was entered manually by the user rather than recorded by a device. */
  manual: boolean;
  /** Per-stage breakdown of the session, ordered by start time. */
  stages: SleepStage[];
}

export interface SleepStage {
  startDate: string;
  endDate: string;
  stage: SleepStageType;
}

export declare type SleepStageType = 'awake' | 'asleep' | 'light' | 'deep' | 'rem' | 'inBed' | 'outOfBed' | 'unknown';
