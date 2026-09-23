import XCTest
import HealthKit
@testable import HealthPluginPlugin

/// Unit tests for the pure mapping functions in `HealthPlugin`.
///
/// Anything that touches `HKHealthStore` needs a real device with HealthKit
/// authorization, so these cover the parts that can be verified in isolation:
/// the data type / permission / unit tables that the JS contract depends on.
final class HealthPluginTests: XCTestCase {

    private var plugin: HealthPlugin!

    override func setUp() {
        super.setUp()
        plugin = HealthPlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - recordTypeDescriptor

    func testRecordTypeDescriptorMapsEverySupportedDataType() {
        let expected: [String: HKQuantityTypeIdentifier] = [
            "steps": .stepCount,
            "flights-climbed": .flightsClimbed,
            "weight": .bodyMass,
            "height": .height,
            "body-fat": .bodyFatPercentage,
            "lean-body-mass": .leanBodyMass
        ]

        for (dataType, identifier) in expected {
            let descriptor = plugin.recordTypeDescriptor(dataType)
            XCTAssertNotNil(descriptor, "expected a descriptor for '\(dataType)'")
            XCTAssertEqual(descriptor?.identifier, identifier, "wrong identifier for '\(dataType)'")
        }
    }

    func testRecordTypeDescriptorReturnsNilForUnsupportedDataType() {
        // Types that exist only in Health Connect, and outright nonsense, must
        // both fall through so queryRecords rejects instead of querying junk.
        XCTAssertNil(plugin.recordTypeDescriptor("bone-mass"))
        XCTAssertNil(plugin.recordTypeDescriptor("body-water-mass"))
        XCTAssertNil(plugin.recordTypeDescriptor("bmi"))
        XCTAssertNil(plugin.recordTypeDescriptor(""))
        XCTAssertNil(plugin.recordTypeDescriptor("Weight"))
    }

    // MARK: - Unit contract shared with Android

    /// The plugin promises JS a single unit per data type regardless of platform
    /// and regardless of the unit HealthKit happens to store. Converting from a
    /// deliberately different source unit proves the conversion, not just the
    /// unit's identity.
    func testWeightIsReportedInKilograms() {
        let descriptor = plugin.recordTypeDescriptor("weight")
        XCTAssertNotNil(descriptor)

        let stored = HKQuantity(unit: HKUnit.pound(), doubleValue: 154.0)
        let value = stored.doubleValue(for: descriptor!.unit) * descriptor!.scale

        XCTAssertEqual(value, 69.8532, accuracy: 0.001)
    }

    func testLeanBodyMassIsReportedInKilograms() {
        let descriptor = plugin.recordTypeDescriptor("lean-body-mass")
        XCTAssertNotNil(descriptor)

        let stored = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: 55.5)
        let value = stored.doubleValue(for: descriptor!.unit) * descriptor!.scale

        XCTAssertEqual(value, 55.5, accuracy: 0.0001)
    }

    func testHeightIsReportedInMeters() {
        let descriptor = plugin.recordTypeDescriptor("height")
        XCTAssertNotNil(descriptor)

        let stored = HKQuantity(unit: HKUnit.inch(), doubleValue: 70.0)
        let value = stored.doubleValue(for: descriptor!.unit) * descriptor!.scale

        XCTAssertEqual(value, 1.778, accuracy: 0.0001)
    }

    /// HealthKit stores body fat as a fraction (0 - 1) while Health Connect uses
    /// 0 - 100. The plugin normalises to 0 - 100, so this guards the scale factor
    /// that keeps both platforms returning the same number.
    func testBodyFatIsScaledToPercent() {
        let descriptor = plugin.recordTypeDescriptor("body-fat")
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.scale, 100)

        let stored = HKQuantity(unit: HKUnit.percent(), doubleValue: 0.235)
        let value = stored.doubleValue(for: descriptor!.unit) * descriptor!.scale

        XCTAssertEqual(value, 23.5, accuracy: 0.0001)
    }

    func testStepsAreNotRescaled() {
        let descriptor = plugin.recordTypeDescriptor("steps")
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.scale, 1)

        let stored = HKQuantity(unit: HKUnit.count(), doubleValue: 1234)
        let value = stored.doubleValue(for: descriptor!.unit) * descriptor!.scale

        XCTAssertEqual(value, 1234, accuracy: 0.0001)
    }

    /// Apple counts flights, Health Connect counts floors, and both call one of
    /// them roughly three meters of climb. They are the same unit, so the plugin
    /// must pass the count through untouched rather than converting anything.
    func testFlightsClimbedIsNotRescaled() {
        let descriptor = plugin.recordTypeDescriptor("flights-climbed")
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.scale, 1)
        XCTAssertEqual(descriptor?.unit, HKUnit.count())

        let stored = HKQuantity(unit: HKUnit.count(), doubleValue: 12)
        let value = stored.doubleValue(for: descriptor!.unit) * descriptor!.scale

        XCTAssertEqual(value, 12, accuracy: 0.0001)
    }

    // MARK: - Permissions

    func testBodyCompositionPermissionsMapToReadTypes() {
        let expected: [String: HKQuantityTypeIdentifier] = [
            "READ_WEIGHT": .bodyMass,
            "READ_HEIGHT": .height,
            "READ_BODY_FAT": .bodyFatPercentage,
            "READ_LEAN_BODY_MASS": .leanBodyMass
        ]

        for (permission, identifier) in expected {
            let readTypes = plugin.permissionToHKObjectReadType(permission)
            XCTAssertEqual(readTypes.count, 1, "expected exactly one read type for \(permission)")
            XCTAssertEqual(readTypes.first, HKObjectType.quantityType(forIdentifier: identifier))
        }
    }

    /// Requesting a data type is useless without the permission that unlocks it,
    /// and an unmapped permission silently reports as granted (the result is
    /// built from the requested names, not the resolved types). This ties the two
    /// tables together so adding a data type without its permission fails here.
    func testEveryRecordDataTypeHasAMatchingPermission() {
        let pairs = [
            ("weight", "READ_WEIGHT"),
            ("height", "READ_HEIGHT"),
            ("body-fat", "READ_BODY_FAT"),
            ("lean-body-mass", "READ_LEAN_BODY_MASS"),
            ("steps", "READ_STEPS"),
            ("flights-climbed", "READ_FLIGHTS_CLIMBED")
        ]

        for (dataType, permission) in pairs {
            guard let descriptor = plugin.recordTypeDescriptor(dataType) else {
                return XCTFail("no descriptor for '\(dataType)'")
            }
            let readTypes = plugin.permissionToHKObjectReadType(permission)
            XCTAssertEqual(
                readTypes.first,
                HKObjectType.quantityType(forIdentifier: descriptor.identifier),
                "'\(dataType)' and \(permission) resolve to different HealthKit types"
            )
        }
    }

    func testUnknownPermissionResolvesToNoReadTypes() {
        XCTAssertTrue(plugin.permissionToHKObjectReadType("READ_BONE_MASS").isEmpty)
        XCTAssertTrue(plugin.permissionToHKObjectReadType("READ_NONSENSE").isEmpty)
    }

    func testOnlyWorkoutsAreWritable() {
        XCTAssertEqual(plugin.permissionToHKObjectWriteType("WRITE_WORKOUTS").count, 1)
        XCTAssertTrue(plugin.permissionToHKObjectWriteType("READ_WEIGHT").isEmpty)
        XCTAssertTrue(plugin.permissionToHKObjectWriteType("WRITE_WEIGHT").isEmpty)
    }

    // MARK: - Aggregation

    /// Body composition is discrete, and queryAggregated sums with
    /// `.cumulativeSum`. Summing weigh-ins is meaningless, so these types must
    /// stay out of the aggregate table.
    func testBodyCompositionIsNotAggregatable() {
        XCTAssertNil(plugin.aggregateTypeToHKQuantityType("weight"))
        XCTAssertNil(plugin.aggregateTypeToHKQuantityType("height"))
        XCTAssertNil(plugin.aggregateTypeToHKQuantityType("body-fat"))
        XCTAssertNil(plugin.aggregateTypeToHKQuantityType("lean-body-mass"))
    }

    /// Flights of stairs are cumulative, so unlike body composition they belong
    /// in the aggregate table - and must resolve to the same HealthKit type that
    /// queryRecords reads, or aggregated and raw results would disagree.
    func testFlightsClimbedIsAggregatable() {
        XCTAssertEqual(
            plugin.aggregateTypeToHKQuantityType("flights-climbed"),
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)
        )
        XCTAssertEqual(
            plugin.aggregateTypeToHKQuantityType("flights-climbed"),
            HKObjectType.quantityType(forIdentifier: plugin.recordTypeDescriptor("flights-climbed")!.identifier)
        )
    }

    func testCalculateIntervalSupportsDocumentedBuckets() {
        XCTAssertEqual(plugin.calculateInterval(bucket: "hour")?.hour, 1)
        XCTAssertEqual(plugin.calculateInterval(bucket: "day")?.day, 1)
        XCTAssertEqual(plugin.calculateInterval(bucket: "week")?.weekOfYear, 1)
        XCTAssertNil(plugin.calculateInterval(bucket: "month"))
        XCTAssertNil(plugin.calculateInterval(bucket: ""))
    }

    // MARK: - Date handling

    /// The formatter is configured with `.withFractionalSeconds`, which makes
    /// them mandatory on input. Callers hit this, so pin the behaviour.
    func testIsoDateFormatterRequiresFractionalSeconds() {
        XCTAssertNotNil(plugin.isoDateFormatter.date(from: "2026-01-01T00:00:00.000Z"))
        XCTAssertNil(plugin.isoDateFormatter.date(from: "2026-01-01T00:00:00Z"))
    }

    // MARK: - Nutrition

    private let mealStart = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01T12:00:00Z
    private let mealEnd = Date(timeIntervalSince1970: 1_767_270_600) // 2026-01-01T12:30:00Z
    private let testSource = NutritionSource(name: "Food App", bundleId: "com.example.food")

    private func nutrientSample(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double,
                                start: Date? = nil, metadata: [String: Any]? = nil) -> HKQuantitySample {
        let date = start ?? mealStart
        return HKQuantitySample(
            type: HKObjectType.quantityType(forIdentifier: identifier)!,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: date,
            end: date,
            metadata: metadata
        )
    }

    private func food(_ samples: [HKSample], start: Date? = nil, metadata: [String: Any]? = nil) -> HKCorrelation {
        return HKCorrelation(
            type: HKCorrelationType.correlationType(forIdentifier: .food)!,
            start: start ?? mealStart,
            end: start ?? mealEnd,
            objects: Set(samples),
            metadata: metadata
        )
    }

    func testReadNutritionRequestsEveryNutrientType() {
        let expected: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
            .dietaryFatSaturated, .dietarySugar, .dietaryFiber
        ]
        let readTypes = Set(plugin.permissionToHKObjectReadType("READ_NUTRITION"))

        XCTAssertEqual(readTypes, Set(expected.map { HKObjectType.quantityType(forIdentifier: $0)! as HKObjectType }))
    }

    /// Each nutrient is summed across the correlation's members of that type and
    /// converted from whatever unit the writing app used.
    func testCorrelationSumsAndConvertsMembers() {
        let correlation = food([
            nutrientSample(.dietaryEnergyConsumed, .kilocalorie(), 150),
            nutrientSample(.dietaryEnergyConsumed, .jouleUnit(with: .kilo), 418.4),
            nutrientSample(.dietaryProtein, .gram(), 10),
            nutrientSample(.dietaryProtein, .gramUnit(with: .milli), 2500),
            nutrientSample(.dietaryCarbohydrates, .ounce(), 1),
            nutrientSample(.dietaryFatTotal, .gram(), 8),
            nutrientSample(.dietaryFatSaturated, .gram(), 3),
            nutrientSample(.dietarySugar, .gram(), 12),
            nutrientSample(.dietaryFiber, .gram(), 4)
        ], metadata: [HKMetadataKeyFoodType: "Porridge"])

        let entry = NutritionMapper.entry(from: correlation, source: testSource)

        XCTAssertEqual(entry.id, correlation.uuid.uuidString)
        XCTAssertEqual(entry.startDate, mealStart)
        XCTAssertEqual(entry.endDate, mealEnd)
        XCTAssertEqual(entry.name, "Porridge")
        XCTAssertEqual(entry.grouping, "correlation")
        XCTAssertEqual(entry.source, testSource)
        XCTAssertEqual(entry.values[.energyKcal]!, 250, accuracy: 0.001)
        XCTAssertEqual(entry.values[.proteinG]!, 12.5, accuracy: 0.001)
        XCTAssertEqual(entry.values[.carbohydratesG]!, 28.3495, accuracy: 0.001)
        XCTAssertEqual(entry.values[.fatG]!, 8, accuracy: 0.001)
        XCTAssertEqual(entry.values[.saturatedFatG]!, 3, accuracy: 0.001)
        XCTAssertEqual(entry.values[.sugarG]!, 12, accuracy: 0.001)
        XCTAssertEqual(entry.values[.fiberG]!, 4, accuracy: 0.001)
    }

    /// A nutrient with no member sample must be absent, not 0 - while a
    /// recorded 0 is real data and must be kept.
    func testCorrelationDistinguishesMissingFromZero() {
        let correlation = food([
            nutrientSample(.dietaryEnergyConsumed, .kilocalorie(), 0),
            nutrientSample(.dietaryProtein, .gram(), 5)
        ])

        let entry = NutritionMapper.entry(from: correlation, source: testSource)
        let js = entry.toJS(plugin.isoDateFormatter)
        let macros = js["macros"] as? [String: Any]

        XCTAssertEqual(js["energyKcal"] as? Double, 0)
        XCTAssertEqual(macros?["proteinG"] as? Double, 5)
        XCTAssertEqual(macros?.count, 1)
        XCTAssertNil(js["name"])
        XCTAssertNil(js["mealType"])
    }

    func testCorrelationIgnoresMembersThatAreNotReadNutrients() {
        let correlation = food([
            nutrientSample(.dietaryCaffeine, .gram(), 0.1),
            nutrientSample(.dietarySugar, .gram(), 20)
        ])

        let entry = NutritionMapper.entry(from: correlation, source: testSource)

        XCTAssertEqual(entry.values.count, 1)
        XCTAssertEqual(entry.values[.sugarG]!, 20, accuracy: 0.001)
    }

    func testSampleEntryHasOnlyItsOwnNutrient() {
        let sample = nutrientSample(.dietaryFiber, .gram(), 6, metadata: [HKMetadataKeyFoodType: "Apple"])

        let entry = NutritionMapper.entry(from: sample, source: testSource)

        XCTAssertEqual(entry?.id, sample.uuid.uuidString)
        XCTAssertEqual(entry?.grouping, "sample")
        XCTAssertEqual(entry?.name, "Apple")
        XCTAssertEqual(entry?.values.count, 1)
        XCTAssertEqual(entry!.values[.fiberG]!, 6, accuracy: 0.001)
    }

    func testSampleEntryRejectsUnsupportedNutrient() {
        XCTAssertNil(NutritionMapper.entry(from: nutrientSample(.dietaryCaffeine, .gram(), 0.1), source: testSource))
    }

    /// Samples inside a returned correlation must not show up again on their
    /// own, or their nutrients would be counted twice.
    func testUngroupedSamplesDropCorrelationMembers() {
        let member = nutrientSample(.dietaryProtein, .gram(), 10)
        let otherMember = nutrientSample(.dietaryEnergyConsumed, .kilocalorie(), 200)
        let loose = nutrientSample(.dietaryProtein, .gram(), 7)
        let correlation = food([member, otherMember])

        let ungrouped = NutritionMapper.ungroupedSamples([member, loose, otherMember], excluding: [correlation])

        XCTAssertEqual(ungrouped.map { $0.uuid }, [loose.uuid])
    }

    func testMealTypeReadsRecognisedHints() {
        XCTAssertEqual(NutritionMapper.mealType(from: ["Meal": "Breakfast"]), "breakfast")
        XCTAssertEqual(NutritionMapper.mealType(from: ["meal_type": " lunch "]), "lunch")
        XCTAssertEqual(NutritionMapper.mealType(from: ["MealType": "DINNER"]), "dinner")
        XCTAssertEqual(NutritionMapper.mealType(from: ["HKFoodMeal": "Snacks"]), "snack")
    }

    /// Without a recognisable hint the meal type stays undefined - no guessing,
    /// and in particular no guessing from the time of day.
    func testMealTypeIsNilWithoutRecognisedHint() {
        XCTAssertNil(NutritionMapper.mealType(from: nil))
        XCTAssertNil(NutritionMapper.mealType(from: [:]))
        XCTAssertNil(NutritionMapper.mealType(from: [HKMetadataKeyFoodType: "Breakfast burrito"]))
        XCTAssertNil(NutritionMapper.mealType(from: ["Meal": "brunch"]))
        XCTAssertNil(NutritionMapper.mealType(from: ["Meal": 1]))

        let correlation = food([nutrientSample(.dietaryProtein, .gram(), 1)])
        XCTAssertNil(NutritionMapper.entry(from: correlation, source: testSource).mealType)
    }

    func testSortAndLimit() {
        let late = NutritionMapper.entry(from: food([nutrientSample(.dietarySugar, .gram(), 1)], start: mealEnd), source: testSource)
        let early = NutritionMapper.entry(from: nutrientSample(.dietarySugar, .gram(), 2), source: testSource)!

        let sorted = NutritionMapper.sortAndLimit([late, early], limit: nil)
        XCTAssertEqual(sorted.map { $0.id }, [early.id, late.id])

        let limited = NutritionMapper.sortAndLimit([late, early], limit: 1)
        XCTAssertEqual(limited.map { $0.id }, [early.id])
    }
}
