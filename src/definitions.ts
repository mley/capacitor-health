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
   * Supports `steps` and the body composition types `weight`, `height`,
   * `body-fat` and `lean-body-mass`. All of them behave identically on Android
   * and iOS - see {@link RecordDataType} for the units.
   *
   * Body composition measurements are taken at a single point in time, so
   * `startDate` and `endDate` of the returned records are equal.
   *
   * @param request
   */
  queryRecords(request: QueryRecordsRequest): Promise<QueryRecordsResponse>;
}

export declare type HealthPermission =
  | 'READ_STEPS'
  | 'READ_WORKOUTS'
  | 'WRITE_WORKOUTS' //needed for iOS, because the Watch App writes workouts
  | 'READ_ACTIVE_CALORIES'
  | 'READ_TOTAL_CALORIES'
  | 'READ_DISTANCE'
  | 'READ_HEART_RATE'
  | 'READ_ROUTE'
  | 'READ_MINDFULNESS'
  | 'READ_WEIGHT'
  | 'READ_HEIGHT'
  | 'READ_BODY_FAT'
  | 'READ_LEAN_BODY_MASS';

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
  dataType: 'steps' | 'active-calories' | 'mindfulness';
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

/**
 * Data types that can be read as individual records via `queryRecords`.
 *
 * The four body composition types behave identically on Android and iOS: same
 * units, same value ranges, same result shape.
 *
 * | dataType           | Permission             | Unit                |
 * |--------------------|------------------------|---------------------|
 * | `steps`            | `READ_STEPS`           | count               |
 * | `weight`           | `READ_WEIGHT`          | kilograms           |
 * | `height`           | `READ_HEIGHT`          | meters              |
 * | `body-fat`         | `READ_BODY_FAT`        | percent (0 - 100)   |
 * | `lean-body-mass`   | `READ_LEAN_BODY_MASS`  | kilograms           |
 */
export declare type RecordDataType = 'steps' | 'weight' | 'height' | 'body-fat' | 'lean-body-mass';

export interface QueryRecordsRequest {
  startDate: string;
  endDate: string;
  dataType: RecordDataType;
}

export interface HealthRecord {
  startDate: string;
  endDate: string;
  value: number;
  sourceBundleId: string;
  sourceName: string;
  manual: boolean;
}

export interface QueryRecordsResponse {
  records: HealthRecord[];
}
