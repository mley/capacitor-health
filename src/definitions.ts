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
   *
   * `flights-climbed` behaves identically on Android and iOS - one flight is
   * roughly three meters of elevation gain on both platforms.
   *
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
   * Supports `steps`, `flights-climbed` and the body composition types
   * `weight`, `height`, `body-fat` and `lean-body-mass`. All of them behave
   * identically on Android and iOS - see {@link RecordDataType} for the units.
   *
   * Body composition measurements are taken at a single point in time, so
   * `startDate` and `endDate` of the returned records are equal.
   *
   * @param request
   */
  queryRecords(request: QueryRecordsRequest): Promise<QueryRecordsResponse>;

  /**
   * Query logged food and meals, with energy and macronutrients.
   *
   * Requires the `READ_NUTRITION` permission. Entries are sorted by
   * `startDate` ascending. Energy is always in kilocalories and macros in
   * grams. A nutrient the source did not record is omitted, never reported
   * as `0`.
   *
   * The platforms store food differently, which shows up in the entry's
   * `grouping`:
   *
   * - Android (Health Connect): every `NutritionRecord` is one entry with
   *   `grouping: 'record'`. Health Connect stores the meal type natively.
   * - iOS (HealthKit): every food correlation (`HKCorrelationType(.food)`) is
   *   one entry with `grouping: 'correlation'`; its nutrients are summed from
   *   the correlation's member samples. HealthKit has no standard meal type,
   *   so `mealType` is usually undefined on iOS.
   * - iOS with `includeUngroupedSamples: true`: nutrient samples that are not
   *   part of any returned food correlation are added as one entry each with
   *   `grouping: 'sample'` and only that one nutrient set. Many apps write
   *   loose samples instead of correlations, so without this option their
   *   data is not returned on iOS.
   *
   * @param request
   */
  queryNutrition(request: QueryNutritionRequest): Promise<QueryNutritionResponse>;
}

export declare type HealthPermission =
  | 'READ_STEPS'
  | 'READ_WORKOUTS'
  | 'WRITE_WORKOUTS' //needed for iOS, because the Watch App writes workouts
  | 'READ_ACTIVE_CALORIES'
  | 'READ_TOTAL_CALORIES'
  | 'READ_DISTANCE'
  | 'READ_FLIGHTS_CLIMBED'
  | 'READ_HEART_RATE'
  | 'READ_ROUTE'
  | 'READ_MINDFULNESS'
  | 'READ_WEIGHT'
  | 'READ_HEIGHT'
  | 'READ_BODY_FAT'
  | 'READ_LEAN_BODY_MASS'
  | 'READ_NUTRITION';

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
  dataType: 'steps' | 'active-calories' | 'flights-climbed' | 'mindfulness';
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
 * All of these behave identically on Android and iOS: same units, same value
 * ranges, same result shape.
 *
 * | dataType           | Permission              | Unit                |
 * |--------------------|-------------------------|---------------------|
 * | `steps`            | `READ_STEPS`            | count               |
 * | `flights-climbed`  | `READ_FLIGHTS_CLIMBED`  | count               |
 * | `weight`           | `READ_WEIGHT`           | kilograms           |
 * | `height`           | `READ_HEIGHT`           | meters              |
 * | `body-fat`         | `READ_BODY_FAT`         | percent (0 - 100)   |
 * | `lean-body-mass`   | `READ_LEAN_BODY_MASS`   | kilograms           |
 *
 * `flights-climbed` counts flights of stairs. Both platforms define one
 * flight as roughly three meters of elevation gain (Apple `flightsClimbed`,
 * Health Connect `FloorsClimbedRecord`). Health Connect can report fractional
 * flights, Apple Health always reports whole ones.
 */
export declare type RecordDataType = 'steps' | 'flights-climbed' | 'weight' | 'height' | 'body-fat' | 'lean-body-mass';

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

/**
 * Meal a nutrition entry belongs to.
 *
 * Android maps Health Connect's `MealType` constants; `MEAL_TYPE_UNKNOWN` and
 * unrecognised values become `'unknown'`. iOS has no standard meal type
 * metadata, so it only sets this when the writing app stored a recognisable
 * meal hint (see README).
 */
export declare type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'unknown';

/**
 * How a nutrition entry was assembled from the platform's data.
 *
 * - `record`: one Health Connect `NutritionRecord` (Android).
 * - `correlation`: one HealthKit food correlation, nutrients summed over its
 *   member samples (iOS).
 * - `sample`: one loose HealthKit nutrient sample that belongs to no returned
 *   correlation (iOS, only with `includeUngroupedSamples`).
 */
export declare type NutritionGrouping = 'record' | 'correlation' | 'sample';

/**
 * Macronutrients of a nutrition entry, in grams. A nutrient the source did
 * not record is omitted, never `0`.
 */
export interface NutritionMacros {
  proteinG?: number;
  carbohydratesG?: number;
  fatG?: number;
  saturatedFatG?: number;
  sugarG?: number;
  fiberG?: number;
}

export interface NutritionEntry {
  /** Health Connect record id (Android) or HealthKit object UUID (iOS). */
  id: string;
  startDate: string;
  endDate: string;
  /** Food or meal name, if the source stored one. */
  name?: string;
  mealType?: MealType;
  /** Energy in kilocalories. Omitted if the source did not record it. */
  energyKcal?: number;
  macros: NutritionMacros;
  /** Package name (Android) or bundle identifier (iOS) of the writing app. */
  sourceBundleId: string;
  /**
   * Name of the writing app. iOS only - Health Connect records carry no app
   * name, so this is omitted on Android.
   */
  sourceName?: string;
  grouping: NutritionGrouping;
}

export interface QueryNutritionRequest {
  startDate: string;
  endDate: string;
  /**
   * Maximum number of entries to return: the earliest `limit` entries after
   * sorting. When omitted, all entries in the range are returned.
   */
  limit?: number;
  /**
   * iOS only; ignored on Android, where every entry is a record. When `true`,
   * nutrient samples that belong to no returned food correlation are returned
   * as individual entries with `grouping: 'sample'`. Defaults to `false`.
   */
  includeUngroupedSamples?: boolean;
}

export interface QueryNutritionResponse {
  entries: NutritionEntry[];
}
