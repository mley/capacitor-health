# capacitor-health

Capacitor plugin to query data from Apple Health and Google Health Connect

## Thanks and attribution

Some parts, concepts and ideas are borrowed from [cordova-plugin-health](https://github.com/dariosalvi78/cordova-plugin-health/). Big thanks to [@dariosalvi78](https://github.com/dariosalvi78) for the support.

## Install

```bash
npm install capacitor-health
npx cap sync
```

## Setup

### iOS

* Make sure your app id has the 'HealthKit' entitlement when this plugin is installed (see iOS dev center).
* Also, make sure your app and App Store description comply with the Apple review guidelines.
* There are two keys to be added to the info.plist file: NSHealthShareUsageDescription and NSHealthUpdateUsageDescription. 

### Android

* Android Manifest in application tag
```xml
        <!-- For supported versions through Android 13, create an activity to show the rationale
    of Health Connect permissions once users click the privacy policy link. -->
        <activity
            android:name="com.fit_up.health.capacitor.PermissionsRationaleActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
            </intent-filter>
        </activity>

        <!-- For versions starting Android 14, create an activity alias to show the rationale
         of Health Connect permissions once users click the privacy policy link. -->
        <activity-alias
            android:name="ViewPermissionUsageActivity"
            android:exported="true"
            android:targetActivity="com.fit_up.health.capacitor.PermissionsRationaleActivity"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
                <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
            </intent-filter>
        </activity-alias>
```

* Android Manifest in root tag
```xml
    <queries>
        <package android:name="com.google.android.apps.healthdata" />
    </queries>
    
    <uses-permission android:name="android.permission.health.READ_STEPS" />
    <uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED" />
    <uses-permission android:name="android.permission.health.READ_TOTAL_CALORIES_BURNED" />
    <uses-permission android:name="android.permission.health.READ_DISTANCE" />
    <uses-permission android:name="android.permission.health.READ_FLOORS_CLIMBED" />
    <uses-permission android:name="android.permission.health.READ_EXERCISE" />
    <uses-permission android:name="android.permission.health.READ_EXERCISE_ROUTE" />
    <uses-permission android:name="android.permission.health.READ_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_WEIGHT" />
    <uses-permission android:name="android.permission.health.READ_HEIGHT" />
    <uses-permission android:name="android.permission.health.READ_BODY_FAT" />
    <uses-permission android:name="android.permission.health.READ_LEAN_BODY_MASS" />
    <uses-permission android:name="android.permission.health.READ_NUTRITION" />
```

Only declare the permissions your app actually requests - Health Connect shows every declared
permission on the consent screen.

## Flights of stairs

`flights-climbed` is available through both `queryAggregated` and `queryRecords`. Apple Health
calls these *flights climbed* and Health Connect calls them *floors climbed*, but both define one
as roughly three meters of elevation gain, so the plugin exposes a single type with one
permission and one unit.

| `dataType` | Permission | Unit | Apple Health | Health Connect |
|---|---|---|---|---|
| `flights-climbed` | `READ_FLIGHTS_CLIMBED` | count | `flightsClimbed` | `FloorsClimbedRecord` |

```typescript
await Health.requestHealthPermissions({ permissions: ['READ_FLIGHTS_CLIMBED'] });

// Aggregated - one total per bucket
const { aggregatedData } = await Health.queryAggregated({
  startDate: '2026-01-01T00:00:00.000Z',
  endDate: '2026-01-08T00:00:00.000Z',
  dataType: 'flights-climbed',
  bucket: 'day',
});
// [{ startDate: '...', endDate: '...', value: 14 }]

// Raw - every record, with the app that wrote it
const { records } = await Health.queryRecords({
  startDate: '2026-01-01T00:00:00.000Z',
  endDate: '2026-01-08T00:00:00.000Z',
  dataType: 'flights-climbed',
});
// [{ startDate: '...', endDate: '...', value: 3, sourceBundleId: '...', sourceName: '...', manual: false }]
```

Notes:

* Health Connect can report fractional flights, Apple Health always reports whole ones.
* Unlike body composition, these records cover a time span, so `startDate` and `endDate` differ.
* The Android permission is `android.permission.health.READ_FLOORS_CLIMBED` - Health Connect names
  it after floors, while the plugin's cross-platform permission is `READ_FLIGHTS_CLIMBED`.
* `queryAggregated` only supports `bucket: 'day'` on Android; `'hour'` and `'week'` work on iOS
  only. That limit applies to every aggregated data type, not just this one.

## Body composition

`queryRecords` reads body composition as individual measurements. The four supported types are
available on both platforms and behave identically - same permission name, same unit, same value
range - so callers do not need to branch on the platform.

| `dataType` | Permission | Unit | Apple Health | Health Connect |
|---|---|---|---|---|
| `weight` | `READ_WEIGHT` | kilograms | `bodyMass` | `WeightRecord` |
| `height` | `READ_HEIGHT` | meters | `height` | `HeightRecord` |
| `body-fat` | `READ_BODY_FAT` | percent (0 - 100) | `bodyFatPercentage` | `BodyFatRecord` |
| `lean-body-mass` | `READ_LEAN_BODY_MASS` | kilograms | `leanBodyMass` | `LeanBodyMassRecord` |

```typescript
await Health.requestHealthPermissions({ permissions: ['READ_WEIGHT', 'READ_BODY_FAT'] });

const { records } = await Health.queryRecords({
  startDate: '2026-01-01T00:00:00.000Z',
  endDate: '2026-02-01T00:00:00.000Z',
  dataType: 'weight',
});
// [{ startDate: '...', endDate: '...', value: 81.4, sourceBundleId: '...', sourceName: '...', manual: false }]
```

Notes:

* These are point-in-time measurements, so `startDate` and `endDate` of each record are equal.
* Apple Health stores body fat as a fraction (0 - 1); the plugin scales it to 0 - 100 to match
  Health Connect.
* `queryAggregated` does not support these types on either platform. They are discrete
  measurements, and summing them is meaningless - four of the underlying Health Connect records
  do not define an aggregate metric at all.
* Bone mass and body water exist only in Health Connect; BMI and waist circumference exist only
  in Apple Health. None of them are exposed, to keep the API platform-independent.
* iOS dates must include fractional seconds (`2026-01-01T00:00:00.000Z`).

## Nutrition

`queryNutrition` reads logged food and meals, with energy and macronutrients. It needs the
`READ_NUTRITION` permission.

```typescript
await Health.requestHealthPermissions({ permissions: ['READ_NUTRITION'] });

const { entries } = await Health.queryNutrition({
  startDate: '2026-01-01T00:00:00.000Z',
  endDate: '2026-01-02T00:00:00.000Z',
  limit: 100, // optional
  includeUngroupedSamples: true, // optional, iOS only
});
// [{
//   id: '...', startDate: '...', endDate: '...',
//   name: 'Porridge', mealType: 'breakfast',
//   energyKcal: 310,
//   macros: { proteinG: 11, carbohydratesG: 54, fatG: 6 },
//   sourceBundleId: 'com.example.food', sourceName: 'Food App',
//   grouping: 'record',
// }]
```

The result shape is the same on both platforms:

* Energy is always kilocalories and macros are always grams, whatever unit the writing app used.
* A nutrient the writing app did not record is left out, never reported as `0`. A recorded `0` is
  kept.
* Entries are sorted by `startDate` ascending. `limit` returns the earliest `limit` entries.

The platforms store food differently, though, so some fields depend on the platform:

| | Android (Health Connect) | iOS (HealthKit) |
|---|---|---|
| One entry is | one `NutritionRecord` | one food correlation (`HKCorrelationType(.food)`), plus loose samples with `includeUngroupedSamples` |
| `grouping` | `'record'` | `'correlation'`, or `'sample'` for loose samples |
| Nutrient values | read from the record | summed over the correlation's member samples |
| `name` | `NutritionRecord.name` | `HKMetadataKeyFoodType` metadata |
| `mealType` | always set; `MEAL_TYPE_UNKNOWN` becomes `'unknown'` | usually undefined - HealthKit has no standard meal type (see below) |
| `sourceName` | omitted - Health Connect records carry no app name | name of the writing app |
| `includeUngroupedSamples` | ignored | see below |
| Permission | `android.permission.health.READ_NUTRITION` | read access to dietary energy, protein, carbohydrates, total fat, saturated fat, sugar and fiber |

Notes:

* **iOS loose samples.** Many apps write single nutrient samples (for example just the energy)
  without wrapping them in a food correlation. These are not returned by default. With
  `includeUngroupedSamples: true`, each sample that is not a member of a returned correlation is
  added as its own entry with `grouping: 'sample'` and only that one nutrient set. Samples are
  never merged into meals heuristically, so one meal can show up as several `sample` entries.
* **iOS meal type.** HealthKit defines no meal type. The plugin only sets `mealType` when the
  correlation's (or sample's) metadata has a key named `Meal`, `MealType`, `meal_type` or
  `HKFoodMeal` (case-insensitive) with the value `breakfast`, `lunch`, `dinner`, `snack` or
  `snacks` (case-insensitive). Anything else leaves it undefined. The meal type is never guessed
  from the time of day.
* **Android history.** Like every other query in this plugin, `queryNutrition` does not request
  `READ_HEALTH_DATA_HISTORY`, so Health Connect only returns data from 30 days before the
  permission was first granted.
* iOS dates must include fractional seconds (`2026-01-01T00:00:00.000Z`).

## API

<docgen-index>

* [`isHealthAvailable()`](#ishealthavailable)
* [`checkHealthPermissions(...)`](#checkhealthpermissions)
* [`requestHealthPermissions(...)`](#requesthealthpermissions)
* [`openAppleHealthSettings()`](#openapplehealthsettings)
* [`openHealthConnectSettings()`](#openhealthconnectsettings)
* [`showHealthConnectInPlayStore()`](#showhealthconnectinplaystore)
* [`queryAggregated(...)`](#queryaggregated)
* [`queryWorkouts(...)`](#queryworkouts)
* [`queryRecords(...)`](#queryrecords)
* [`queryNutrition(...)`](#querynutrition)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### isHealthAvailable()

```typescript
isHealthAvailable() => Promise<{ available: boolean; }>
```

Checks if health API is available.
Android: If false is returned, the Google Health Connect app is probably not installed.
See showHealthConnectInPlayStore()

**Returns:** <code>Promise&lt;{ available: boolean; }&gt;</code>

--------------------


### checkHealthPermissions(...)

```typescript
checkHealthPermissions(permissions: PermissionsRequest) => Promise<PermissionResponse>
```

Android only: Returns for each given permission, if it was granted by the underlying health API

| Param             | Type                                                              | Description          |
| ----------------- | ----------------------------------------------------------------- | -------------------- |
| **`permissions`** | <code><a href="#permissionsrequest">PermissionsRequest</a></code> | permissions to query |

**Returns:** <code>Promise&lt;<a href="#permissionresponse">PermissionResponse</a>&gt;</code>

--------------------


### requestHealthPermissions(...)

```typescript
requestHealthPermissions(permissions: PermissionsRequest) => Promise<PermissionResponse>
```

Requests the permissions from the user.

Android: Apps can ask only a few times for permissions, after that the user has to grant them manually in
the Health Connect app. See openHealthConnectSettings()

iOS: If the permissions are already granted or denied, this method will just return without asking the user. In iOS
we can't really detect if a user granted or denied a permission. The return value reflects the assumption that all
permissions were granted.

| Param             | Type                                                              | Description            |
| ----------------- | ----------------------------------------------------------------- | ---------------------- |
| **`permissions`** | <code><a href="#permissionsrequest">PermissionsRequest</a></code> | permissions to request |

**Returns:** <code>Promise&lt;<a href="#permissionresponse">PermissionResponse</a>&gt;</code>

--------------------


### openAppleHealthSettings()

```typescript
openAppleHealthSettings() => Promise<void>
```

Opens the apps settings, which is kind of wrong, because health permissions are configured under:
Settings &gt; Apps &gt; (Apple) Health &gt; Access and Devices &gt; [app-name]
But we can't go there directly.

--------------------


### openHealthConnectSettings()

```typescript
openHealthConnectSettings() => Promise<void>
```

Opens the Google Health Connect app

--------------------


### showHealthConnectInPlayStore()

```typescript
showHealthConnectInPlayStore() => Promise<void>
```

Opens the Google Health Connect app in PlayStore

--------------------


### queryAggregated(...)

```typescript
queryAggregated(request: QueryAggregatedRequest) => Promise<QueryAggregatedResponse>
```

Query aggregated data

`flights-climbed` behaves identically on Android and iOS - one flight is
roughly three meters of elevation gain on both platforms.

| Param         | Type                                                                      |
| ------------- | ------------------------------------------------------------------------- |
| **`request`** | <code><a href="#queryaggregatedrequest">QueryAggregatedRequest</a></code> |

**Returns:** <code>Promise&lt;<a href="#queryaggregatedresponse">QueryAggregatedResponse</a>&gt;</code>

--------------------


### queryWorkouts(...)

```typescript
queryWorkouts(request: QueryWorkoutRequest) => Promise<QueryWorkoutResponse>
```

Query workouts

| Param         | Type                                                                |
| ------------- | ------------------------------------------------------------------- |
| **`request`** | <code><a href="#queryworkoutrequest">QueryWorkoutRequest</a></code> |

**Returns:** <code>Promise&lt;<a href="#queryworkoutresponse">QueryWorkoutResponse</a>&gt;</code>

--------------------


### queryRecords(...)

```typescript
queryRecords(request: QueryRecordsRequest) => Promise<QueryRecordsResponse>
```

Query individual records for a given data type. Unlike queryAggregated,
this returns each record separately with its data origin, which is useful
for detecting duplicate sources.

Supports `steps`, `flights-climbed` and the body composition types
`weight`, `height`, `body-fat` and `lean-body-mass`. All of them behave
identically on Android and iOS - see {@link <a href="#recorddatatype">RecordDataType</a>} for the units.

Body composition measurements are taken at a single point in time, so
`startDate` and `endDate` of the returned records are equal.

| Param         | Type                                                                |
| ------------- | ------------------------------------------------------------------- |
| **`request`** | <code><a href="#queryrecordsrequest">QueryRecordsRequest</a></code> |

**Returns:** <code>Promise&lt;<a href="#queryrecordsresponse">QueryRecordsResponse</a>&gt;</code>

--------------------


### queryNutrition(...)

```typescript
queryNutrition(request: QueryNutritionRequest) => Promise<QueryNutritionResponse>
```

Query logged food and meals, with energy and macronutrients.

Requires the `READ_NUTRITION` permission. Entries are sorted by
`startDate` ascending. Energy is always in kilocalories and macros in
grams. A nutrient the source did not record is omitted, never reported
as `0`.

The platforms store food differently, which shows up in the entry's
`grouping`:

- Android (Health Connect): every `NutritionRecord` is one entry with
  `grouping: 'record'`. Health Connect stores the meal type natively.
- iOS (HealthKit): every food correlation (`HKCorrelationType(.food)`) is
  one entry with `grouping: 'correlation'`; its nutrients are summed from
  the correlation's member samples. HealthKit has no standard meal type,
  so `mealType` is usually undefined on iOS.
- iOS with `includeUngroupedSamples: true`: nutrient samples that are not
  part of any returned food correlation are added as one entry each with
  `grouping: 'sample'` and only that one nutrient set. Many apps write
  loose samples instead of correlations, so without this option their
  data is not returned on iOS.

| Param         | Type                                                                    |
| ------------- | ----------------------------------------------------------------------- |
| **`request`** | <code><a href="#querynutritionrequest">QueryNutritionRequest</a></code> |

**Returns:** <code>Promise&lt;<a href="#querynutritionresponse">QueryNutritionResponse</a>&gt;</code>

--------------------


### Interfaces


#### PermissionResponse

| Prop              | Type                                       |
| ----------------- | ------------------------------------------ |
| **`permissions`** | <code>{ [key: string]: boolean; }[]</code> |


#### PermissionsRequest

| Prop              | Type                            |
| ----------------- | ------------------------------- |
| **`permissions`** | <code>HealthPermission[]</code> |


#### QueryAggregatedResponse

| Prop                 | Type                            |
| -------------------- | ------------------------------- |
| **`aggregatedData`** | <code>AggregatedSample[]</code> |


#### AggregatedSample

| Prop            | Type                |
| --------------- | ------------------- |
| **`startDate`** | <code>string</code> |
| **`endDate`**   | <code>string</code> |
| **`value`**     | <code>number</code> |


#### QueryAggregatedRequest

| Prop              | Type                                                                            | Description                                                                                                                                                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **`startDate`**   | <code>string</code>                                                             |                                                                                                                                                                                                                                                  |
| **`endDate`**     | <code>string</code>                                                             |                                                                                                                                                                                                                                                  |
| **`dataType`**    | <code>'steps' \| 'active-calories' \| 'flights-climbed' \| 'mindfulness'</code> |                                                                                                                                                                                                                                                  |
| **`bucket`**      | <code>string</code>                                                             |                                                                                                                                                                                                                                                  |
| **`dataOrigins`** | <code>string[]</code>                                                           | Optional list of package names (Android) or bundle identifiers (iOS) to restrict the aggregation to. When omitted or empty, data from all sources is included. Example: `['com.sec.android.app.shealth']` to only aggregate Samsung Health data. |


#### QueryWorkoutResponse

| Prop           | Type                   |
| -------------- | ---------------------- |
| **`workouts`** | <code>Workout[]</code> |


#### Workout

| Prop                 | Type                           |
| -------------------- | ------------------------------ |
| **`startDate`**      | <code>string</code>            |
| **`endDate`**        | <code>string</code>            |
| **`workoutType`**    | <code>string</code>            |
| **`sourceName`**     | <code>string</code>            |
| **`id`**             | <code>string</code>            |
| **`duration`**       | <code>number</code>            |
| **`distance`**       | <code>number</code>            |
| **`steps`**          | <code>number</code>            |
| **`calories`**       | <code>number</code>            |
| **`sourceBundleId`** | <code>string</code>            |
| **`route`**          | <code>RouteSample[]</code>     |
| **`heartRate`**      | <code>HeartRateSample[]</code> |


#### RouteSample

| Prop            | Type                |
| --------------- | ------------------- |
| **`timestamp`** | <code>string</code> |
| **`lat`**       | <code>number</code> |
| **`lng`**       | <code>number</code> |
| **`alt`**       | <code>number</code> |


#### HeartRateSample

| Prop            | Type                |
| --------------- | ------------------- |
| **`timestamp`** | <code>string</code> |
| **`bpm`**       | <code>number</code> |


#### QueryWorkoutRequest

| Prop                   | Type                 |
| ---------------------- | -------------------- |
| **`startDate`**        | <code>string</code>  |
| **`endDate`**          | <code>string</code>  |
| **`includeHeartRate`** | <code>boolean</code> |
| **`includeRoute`**     | <code>boolean</code> |
| **`includeSteps`**     | <code>boolean</code> |


#### QueryRecordsResponse

| Prop          | Type                        |
| ------------- | --------------------------- |
| **`records`** | <code>HealthRecord[]</code> |


#### HealthRecord

| Prop                 | Type                 |
| -------------------- | -------------------- |
| **`startDate`**      | <code>string</code>  |
| **`endDate`**        | <code>string</code>  |
| **`value`**          | <code>number</code>  |
| **`sourceBundleId`** | <code>string</code>  |
| **`sourceName`**     | <code>string</code>  |
| **`manual`**         | <code>boolean</code> |


#### QueryRecordsRequest

| Prop            | Type                                                      |
| --------------- | --------------------------------------------------------- |
| **`startDate`** | <code>string</code>                                       |
| **`endDate`**   | <code>string</code>                                       |
| **`dataType`**  | <code><a href="#recorddatatype">RecordDataType</a></code> |


#### QueryNutritionResponse

| Prop          | Type                          |
| ------------- | ----------------------------- |
| **`entries`** | <code>NutritionEntry[]</code> |


#### NutritionEntry

| Prop                 | Type                                                            | Description                                                                                                  |
| -------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **`id`**             | <code>string</code>                                             | Health Connect record id (Android) or HealthKit object UUID (iOS).                                           |
| **`startDate`**      | <code>string</code>                                             |                                                                                                              |
| **`endDate`**        | <code>string</code>                                             |                                                                                                              |
| **`name`**           | <code>string</code>                                             | Food or meal name, if the source stored one.                                                                 |
| **`mealType`**       | <code><a href="#mealtype">MealType</a></code>                   |                                                                                                              |
| **`energyKcal`**     | <code>number</code>                                             | Energy in kilocalories. Omitted if the source did not record it.                                             |
| **`macros`**         | <code><a href="#nutritionmacros">NutritionMacros</a></code>     |                                                                                                              |
| **`sourceBundleId`** | <code>string</code>                                             | Package name (Android) or bundle identifier (iOS) of the writing app.                                        |
| **`sourceName`**     | <code>string</code>                                             | Name of the writing app. iOS only - Health Connect records carry no app name, so this is omitted on Android. |
| **`grouping`**       | <code><a href="#nutritiongrouping">NutritionGrouping</a></code> |                                                                                                              |


#### NutritionMacros

Macronutrients of a nutrition entry, in grams. A nutrient the source did
not record is omitted, never `0`.

| Prop                 | Type                |
| -------------------- | ------------------- |
| **`proteinG`**       | <code>number</code> |
| **`carbohydratesG`** | <code>number</code> |
| **`fatG`**           | <code>number</code> |
| **`saturatedFatG`**  | <code>number</code> |
| **`sugarG`**         | <code>number</code> |
| **`fiberG`**         | <code>number</code> |


#### QueryNutritionRequest

| Prop                          | Type                 | Description                                                                                                                                                                                                               |
| ----------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`startDate`**               | <code>string</code>  |                                                                                                                                                                                                                           |
| **`endDate`**                 | <code>string</code>  |                                                                                                                                                                                                                           |
| **`limit`**                   | <code>number</code>  | Maximum number of entries to return: the earliest `limit` entries after sorting. When omitted, all entries in the range are returned.                                                                                     |
| **`includeUngroupedSamples`** | <code>boolean</code> | iOS only; ignored on Android, where every entry is a record. When `true`, nutrient samples that belong to no returned food correlation are returned as individual entries with `grouping: 'sample'`. Defaults to `false`. |


### Type Aliases


#### HealthPermission

<code>'READ_STEPS' | 'READ_WORKOUTS' | 'WRITE_WORKOUTS' | 'READ_ACTIVE_CALORIES' | 'READ_TOTAL_CALORIES' | 'READ_DISTANCE' | 'READ_FLIGHTS_CLIMBED' | 'READ_HEART_RATE' | 'READ_ROUTE' | 'READ_MINDFULNESS' | 'READ_WEIGHT' | 'READ_HEIGHT' | 'READ_BODY_FAT' | 'READ_LEAN_BODY_MASS' | 'READ_NUTRITION'</code>


#### RecordDataType

Data types that can be read as individual records via `queryRecords`.

All of these behave identically on Android and iOS: same units, same value
ranges, same result shape.

| dataType           | Permission              | Unit                |
|--------------------|-------------------------|---------------------|
| `steps`            | `READ_STEPS`            | count               |
| `flights-climbed`  | `READ_FLIGHTS_CLIMBED`  | count               |
| `weight`           | `READ_WEIGHT`           | kilograms           |
| `height`           | `READ_HEIGHT`           | meters              |
| `body-fat`         | `READ_BODY_FAT`         | percent (0 - 100)   |
| `lean-body-mass`   | `READ_LEAN_BODY_MASS`   | kilograms           |

`flights-climbed` counts flights of stairs. Both platforms define one
flight as roughly three meters of elevation gain (Apple `flightsClimbed`,
Health Connect `FloorsClimbedRecord`). Health Connect can report fractional
flights, Apple Health always reports whole ones.

<code>'steps' | 'flights-climbed' | 'weight' | 'height' | 'body-fat' | 'lean-body-mass'</code>


#### MealType

Meal a nutrition entry belongs to.

Android maps Health Connect's <a href="#mealtype">`MealType`</a> constants; `MEAL_TYPE_UNKNOWN` and
unrecognised values become `'unknown'`. iOS has no standard meal type
metadata, so it only sets this when the writing app stored a recognisable
meal hint (see README).

<code>'breakfast' | 'lunch' | 'dinner' | 'snack' | 'unknown'</code>


#### NutritionGrouping

How a nutrition entry was assembled from the platform's data.

- `record`: one Health Connect `NutritionRecord` (Android).
- `correlation`: one HealthKit food correlation, nutrients summed over its
  member samples (iOS).
- `sample`: one loose HealthKit nutrient sample that belongs to no returned
  correlation (iOS, only with `includeUngroupedSamples`).

<code>'record' | 'correlation' | 'sample'</code>

</docgen-api>
