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
    func testEveryBodyCompositionDataTypeHasAMatchingPermission() {
        let pairs = [
            ("weight", "READ_WEIGHT"),
            ("height", "READ_HEIGHT"),
            ("body-fat", "READ_BODY_FAT"),
            ("lean-body-mass", "READ_LEAN_BODY_MASS"),
            ("steps", "READ_STEPS")
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
}
