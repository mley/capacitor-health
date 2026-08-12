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
    <uses-permission android:name="android.permission.health.READ_EXERCISE" />
    <uses-permission android:name="android.permission.health.READ_EXERCISE_ROUTE" />
    <uses-permission android:name="android.permission.health.READ_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_WEIGHT" />
    <uses-permission android:name="android.permission.health.READ_HEIGHT" />
    <uses-permission android:name="android.permission.health.READ_BODY_FAT" />
    <uses-permission android:name="android.permission.health.READ_LEAN_BODY_MASS" />
```

Only declare the permissions your app actually requests - Health Connect shows every declared
permission on the consent screen.

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

Supports `steps` and the body composition types `weight`, `height`,
`body-fat` and `lean-body-mass`. All of them behave identically on Android
and iOS - see {@link <a href="#recorddatatype">RecordDataType</a>} for the units.

Body composition measurements are taken at a single point in time, so
`startDate` and `endDate` of the returned records are equal.

| Param         | Type                                                                |
| ------------- | ------------------------------------------------------------------- |
| **`request`** | <code><a href="#queryrecordsrequest">QueryRecordsRequest</a></code> |

**Returns:** <code>Promise&lt;<a href="#queryrecordsresponse">QueryRecordsResponse</a>&gt;</code>

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

| Prop              | Type                                                       | Description                                                                                                                                                                                                                                      |
| ----------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **`startDate`**   | <code>string</code>                                        |                                                                                                                                                                                                                                                  |
| **`endDate`**     | <code>string</code>                                        |                                                                                                                                                                                                                                                  |
| **`dataType`**    | <code>'steps' \| 'active-calories' \| 'mindfulness'</code> |                                                                                                                                                                                                                                                  |
| **`bucket`**      | <code>string</code>                                        |                                                                                                                                                                                                                                                  |
| **`dataOrigins`** | <code>string[]</code>                                      | Optional list of package names (Android) or bundle identifiers (iOS) to restrict the aggregation to. When omitted or empty, data from all sources is included. Example: `['com.sec.android.app.shealth']` to only aggregate Samsung Health data. |


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


### Type Aliases


#### HealthPermission

<code>'READ_STEPS' | 'READ_WORKOUTS' | 'WRITE_WORKOUTS' | 'READ_ACTIVE_CALORIES' | 'READ_TOTAL_CALORIES' | 'READ_DISTANCE' | 'READ_HEART_RATE' | 'READ_ROUTE' | 'READ_MINDFULNESS' | 'READ_WEIGHT' | 'READ_HEIGHT' | 'READ_BODY_FAT' | 'READ_LEAN_BODY_MASS'</code>


#### RecordDataType

Data types that can be read as individual records via `queryRecords`.

The four body composition types behave identically on Android and iOS: same
units, same value ranges, same result shape.

| dataType           | Permission             | Unit                |
|--------------------|------------------------|---------------------|
| `steps`            | `READ_STEPS`           | count               |
| `weight`           | `READ_WEIGHT`          | kilograms           |
| `height`           | `READ_HEIGHT`          | meters              |
| `body-fat`         | `READ_BODY_FAT`        | percent (0 - 100)   |
| `lean-body-mass`   | `READ_LEAN_BODY_MASS`  | kilograms           |

<code>'steps' | 'weight' | 'height' | 'body-fat' | 'lean-body-mass'</code>

</docgen-api>
