import Foundation
import Capacitor
import HealthKit

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(HealthPlugin)
public class HealthPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HealthPlugin"
    public let jsName = "HealthPlugin"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isHealthAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkHealthPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestHealthPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openAppleHealthSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryAggregated", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryWorkouts", returnType: CAPPluginReturnPromise)
    ]

    let healthStore = HKHealthStore()

    @objc func isHealthAvailable(_ call: CAPPluginCall) {
        let isAvailable = HKHealthStore.isHealthDataAvailable()
        call.resolve(["available": isAvailable])
    }

    @objc func checkHealthPermissions(_ call: CAPPluginCall) {
        call.reject("not implemented")
    }

    @objc func requestHealthPermissions(_ call: CAPPluginCall) {
        guard let permissions = call.getArray("permissions") as? [String] else {
            call.reject("Invalid permissions format")
            return
        }

        let types: [HKObjectType] = permissions.flatMap { permissionToHKObjectType($0) }

        healthStore.requestAuthorization(toShare: nil, read: Set(types)) { success, error in
            if success {
                // we don't know which actual permissions were granted, so we assume all
                var result: [String: Bool] = [:]
                permissions.forEach { result[$0] = true }
                call.resolve(["permissions": result])
            } else if let error = error {
                call.reject("Authorization failed: \(error.localizedDescription)")
            } else {
                // assume no permissions were granted. We can ask user to adjust them manually
                var result: [String: Bool] = [:]
                permissions.forEach { result[$0] = false }
                call.resolve(["permissions": result])
            }
        }
    }

    @objc func openAppleHealthSettings(_ call: CAPPluginCall) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                call.resolve()
            }
        } else {
            call.reject("Unable to open app-specific settings")
        }
    }

    // Permission helpers
    func permissionToHKObjectType(_ permission: String) -> [HKObjectType] {
        switch permission {
        case "READ_STEPS":
            return [HKObjectType.quantityType(forIdentifier: .stepCount)].compactMap {$0}
        case "READ_ACTIVE_CALORIES":
            return [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)].compactMap {$0}
        case "READ_WORKOUTS":
            return [HKObjectType.workoutType()].compactMap {$0}
        case "READ_HEART_RATE":
            return  [HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap {$0}
        case "READ_RESTING_HEART_RATE":
            return  [HKObjectType.quantityType(forIdentifier: .restingHeartRate)].compactMap {$0}
        case "READ_HRV":
            return  [HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)].compactMap {$0}
        case "READ_STAND_TIME":
            return  [HKObjectType.quantityType(forIdentifier: .appleStandTime)].compactMap {$0}
        case "READ_ROUTE":
            return  [HKSeriesType.workoutRoute()].compactMap {$0}
        case "READ_DISTANCE":
            return [
                HKObjectType.quantityType(forIdentifier: .distanceCycling),
                HKObjectType.quantityType(forIdentifier: .distanceSwimming),
                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
                HKObjectType.quantityType(forIdentifier: .distanceDownhillSnowSports)
            ].compactMap {$0}
        default:
            return []
        }
    }

    func aggregateTypeToHKQuantityType(_ dataType: String) -> HKQuantityType? {
        switch dataType {
        case "steps":
            return HKObjectType.quantityType(forIdentifier: .stepCount)
        case "active-calories":
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case "hrv":
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case "resting-heart-rate":
            return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case "stand-time":
            return HKObjectType.quantityType(forIdentifier: .appleStandTime)
        default:
            return nil
        }
    }

    @objc func queryAggregated(_ call: CAPPluginCall) {
        guard let startDateString = call.getString("startDate"),
              let endDateString = call.getString("endDate"),
              let dataTypeString = call.getString("dataType"),
              let bucket = call.getString("bucket"),
              let startDate = self.isoDateFormatter.date(from: startDateString),
              let endDate = self.isoDateFormatter.date(from: endDateString) else {
            call.reject("Invalid parameters")
            return
        }

        guard let dataType = aggregateTypeToHKQuantityType(dataTypeString) else {
            call.reject("Invalid data type")
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        guard let interval = calculateInterval(bucket: bucket) else {
            call.reject("Invalid bucket")
            return
        }

        let query = HKStatisticsCollectionQuery(
            quantityType: dataType,
            quantitySamplePredicate: predicate,
            options: [.cumulativeSum],
            anchorDate: startDate,
            intervalComponents: interval
        )

        query.initialResultsHandler = { _, result, error in
            if let error = error {
                call.reject("Error fetching aggregated data: \(error.localizedDescription)")
                return
            }

            var aggregatedSamples: [[String: Any]] = []

            result?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                if let sum = statistics.sumQuantity() {
                    let startDate = statistics.startDate.timeIntervalSince1970 * 1000
                    let endDate = statistics.endDate.timeIntervalSince1970 * 1000

                    var value: Double = -1.0
                    if dataTypeString == "steps" && dataType.is(compatibleWith: HKUnit.count()) {
                        value = sum.doubleValue(for: HKUnit.count())
                    } else if dataTypeString == "active-calories" && dataType.is(compatibleWith: HKUnit.kilocalorie()) {
                        value = sum.doubleValue(for: HKUnit.kilocalorie())
                    } else if dataTypeString == "hrv" && dataType.is(compatibleWith: HKUnit.second()) {
                        value = sum.doubleValue(for: HKUnit.second())
                    } else if dataTypeString == "resting-heart-rate" && dataType.is(compatibleWith: HKUnit.count().unitDivided(by: HKUnit.minute())) {
                        value = sum.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                    } else if dataTypeString == "stand-time" && dataType.is(compatibleWith: HKUnit.second()) {
                        value = sum.doubleValue(for: HKUnit.second())
                    }

                    aggregatedSamples.append([
                        "startDate": startDate,
                        "endDate": endDate,
                        "value": value
                    ])
                }
            }

            call.resolve(["aggregatedData": aggregatedSamples])
        }

        healthStore.execute(query)
    }

    private func queryAggregated(for startDate: Date, for endDate: Date, for dataType: HKQuantityType?, completion: @escaping (Double?) -> Void) {

        guard let quantityType = dataType else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            guard let result = result, let sum = result.sumQuantity() else {
                completion(0.0)
                return
            }
            completion(sum.doubleValue(for: HKUnit.count()))
        }

        healthStore.execute(query)

    }

    func calculateInterval(bucket: String) -> DateComponents? {
        switch bucket {
        case "hour":
            return DateComponents(hour: 1)
        case "day":
            return DateComponents(day: 1)
        case "week":
            return DateComponents(weekOfYear: 1)
        default:
            return nil
        }
    }

    var isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    @objc func queryWorkouts(_ call: CAPPluginCall) {
        guard let startDateString =  call.getString("startDate"),
              let endDateString = call.getString("endDate"),
              let includeHeartRate = call.getBool("includeHeartRate"),
              let includeRoute = call.getBool("includeRoute"),
              let includeSteps = call.getBool("includeSteps"),
              let startDate = self.isoDateFormatter.date(from: startDateString),
              let endDate = self.isoDateFormatter.date(from: endDateString) else {
            call.reject("Invalid parameters")
            return
        }

        // Create a predicate to filter workouts by date
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let workoutQuery = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            if let error = error {
                call.reject("Error querying workouts: \(error.localizedDescription)")
                return
            }

            guard let workouts = samples as? [HKWorkout] else {
                call.resolve(["workouts": []])
                return
            }

            var workoutList: [[String: Any]] = []
            var errors: [String: String] = [:]
            let dispatchGroup = DispatchGroup()

            // Process each workout
            for workout in workouts {
                var workoutDict: [String: Any] = [
                    "startDate": workout.startDate,
                    "endDate": workout.endDate,
                    "workoutType": self.workoutTypeMapping[workout.workoutActivityType.rawValue, default: "other"],
                    "sourceName": workout.sourceRevision.source.name,
                    "sourceBundleId": workout.sourceRevision.source.bundleIdentifier,
                    "id": workout.uuid.uuidString,
                    "duration": workout.duration,
                    "calories": workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                    "distance": workout.totalDistance?.doubleValue(for: .meter()) ?? 0
                ]

                var heartRateSamples: [[String: Any]] = []
                var routeSamples: [[String: Any]] = []

                // Query heart rate data if requested
                if includeHeartRate {
                    dispatchGroup.enter()
                    self.queryHeartRate(for: workout, completion: { (heartRates, error) in
                        if error != nil {
                            errors["heart-rate"] = error
                        }
                        heartRateSamples = heartRates
                        dispatchGroup.leave()
                    })
                }

                // Query route data if requested
                if includeRoute {
                    dispatchGroup.enter()
                    self.queryRoute(for: workout, completion: { (routes, error) in
                        if error != nil {
                            errors["route"] = error
                        }
                        routeSamples = routes
                        dispatchGroup.leave()
                    })
                }

                if includeSteps {
                    dispatchGroup.enter()
                    self.queryAggregated(for: workout.startDate, for: workout.endDate, for: HKObjectType.quantityType(forIdentifier: .stepCount), completion: { (steps) in
                        if steps != nil {
                            workoutDict["steps"] = steps
                        }
                        dispatchGroup.leave()
                    })
                }

                dispatchGroup.notify(queue: .main) {
                    workoutDict["heartRate"] = heartRateSamples
                    workoutDict["route"] = routeSamples
                    workoutList.append(workoutDict)
                }

            }

            dispatchGroup.notify(queue: .main) {
                call.resolve(["workouts": workoutList, "errors": errors])
            }
        }

        healthStore.execute(workoutQuery)
    }

    // MARK: - Query Heart Rate Data
    private func queryHeartRate(for workout: HKWorkout, completion: @escaping ([[String: Any]], String?) -> Void) {
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)

        let heartRateQuery = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            guard let heartRateSamplesData =  samples as? [HKQuantitySample], error == nil else {
                completion([], error?.localizedDescription)
                return
            }

            var heartRateSamples: [[String: Any]] = []

            for sample in heartRateSamplesData {
                let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())

                let sampleDict: [String: Any] = [
                    "timestamp": sample.startDate,
                    "bpm": sample.quantity.doubleValue(for: heartRateUnit)
                ]

                heartRateSamples.append(sampleDict)
            }

            completion(heartRateSamples, nil)
        }

        healthStore.execute(heartRateQuery)
    }

    // MARK: - Query Route Data
    private func queryRoute(for workout: HKWorkout, completion: @escaping ([[String: Any]], String?) -> Void) {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)

        let routeQuery = HKSampleQuery(sampleType: routeType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            guard let routes = samples as? [HKWorkoutRoute], error == nil else {
                completion([], error?.localizedDescription)
                return
            }

            var routeLocations: [[String: Any]] = []
            let routeDispatchGroup = DispatchGroup()

            // Query locations for each route
            for route in routes {
                routeDispatchGroup.enter()
                self.queryLocations(for: route) { locations in
                    routeLocations.append(contentsOf: locations)
                    routeDispatchGroup.leave()
                }
            }

            routeDispatchGroup.notify(queue: .main) {
                completion(routeLocations, nil)
            }
        }

        healthStore.execute(routeQuery)
    }

    // MARK: - Query Route Locations
    private func queryLocations(for route: HKWorkoutRoute, completion: @escaping ([[String: Any]]) -> Void) {
        var routeLocations: [[String: Any]] = []

        let locationQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
            guard let locations = locations, error == nil else {
                completion([])
                return
            }

            for location in locations {
                let locationDict: [String: Any] = [
                    "timestamp": location.timestamp,
                    "lat": location.coordinate.latitude,
                    "lng": location.coordinate.longitude,
                    "alt": location.altitude
                ]
                routeLocations.append(locationDict)
            }

            if done {
                completion(routeLocations)
            }
        }

        healthStore.execute(locationQuery)
    }

    let workoutTypeMapping: [UInt: String] =  [
        1: "americanFootball",
        2: "archery",
        3: "australianFootball",
        4: "badminton",
        5: "baseball",
        6: "basketball",
        7: "bowling",
        8: "boxing",
        9: "climbing",
        10: "cricket",
        11: "crossTraining",
        12: "curling",
        13: "cycling",
        14: "dance",
        15: "danceInspiredTraining",
        16: "elliptical",
        17: "equestrianSports",
        18: "fencing",
        19: "fishing",
        20: "functionalStrengthTraining",
        21: "golf",
        22: "gymnastics",
        23: "handball",
        24: "hiking",
        25: "hockey",
        26: "hunting",
        27: "lacrosse",
        28: "martialArts",
        29: "mindAndBody",
        30: "mixedMetabolicCardioTraining",
        31: "paddleSports",
        32: "play",
        33: "preparationAndRecovery",
        34: "racquetball",
        35: "rowing",
        36: "rugby",
        37: "running",
        38: "sailing",
        39: "skatingSports",
        40: "snowSports",
        41: "soccer",
        42: "softball",
        43: "squash",
        44: "stairClimbing",
        45: "surfingSports",
        46: "swimming",
        47: "tableTennis",
        48: "tennis",
        49: "trackAndField",
        50: "traditionalStrengthTraining",
        51: "volleyball",
        52: "walking",
        53: "waterFitness",
        54: "waterPolo",
        55: "waterSports",
        56: "wrestling",
        57: "yoga",
        58: "barre",
        59: "coreTraining",
        60: "crossCountrySkiing",
        61: "downhillSkiing",
        62: "flexibility",
        63: "highIntensityIntervalTraining",
        64: "jumpRope",
        65: "kickboxing",
        66: "pilates",
        67: "snowboarding",
        68: "stairs",
        69: "stepTraining",
        70: "wheelchairWalkPace",
        71: "wheelchairRunPace",
        72: "taiChi",
        73: "mixedCardio",
        74: "handCycling",
        75: "discSports",
        76: "fitnessGaming",
        77: "cardioDance",
        78: "socialDance",
        79: "pickleball",
        80: "cooldown",
        82: "swimBikeRun",
        83: "transition",
        84: "underwaterDiving",
        3000: "other"
    ]

}
