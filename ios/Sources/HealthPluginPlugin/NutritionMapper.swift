import Foundation
import HealthKit

/// Where a nutrition entry came from. Passed in explicitly rather than read from
/// `sourceRevision`, so the mapper works on unsaved objects in unit tests.
struct NutritionSource: Equatable {
    let name: String?
    let bundleId: String

    init(name: String?, bundleId: String) {
        self.name = name
        self.bundleId = bundleId
    }

    init(_ object: HKObject) {
        self.init(name: object.sourceRevision.source.name, bundleId: object.sourceRevision.source.bundleIdentifier)
    }
}

/// One `queryNutrition` entry, before it is serialized to JS.
///
/// A nutrient that the source did not record has no key in `values` - it is
/// omitted from the JS result, never reported as 0.
struct NutritionEntry {
    enum Field: String, CaseIterable {
        case energyKcal, proteinG, carbohydratesG, fatG, saturatedFatG, sugarG, fiberG
    }

    let id: String
    let startDate: Date
    let endDate: Date
    let name: String?
    let mealType: String?
    let values: [Field: Double]
    let source: NutritionSource
    let grouping: String

    func toJS(_ formatter: ISO8601DateFormatter) -> [String: Any] {
        var macros: [String: Any] = [:]
        for field in Field.allCases where field != .energyKcal {
            if let value = values[field] {
                macros[field.rawValue] = value
            }
        }

        var result: [String: Any] = [
            "id": id,
            "startDate": formatter.string(from: startDate),
            "endDate": formatter.string(from: endDate),
            "macros": macros,
            "sourceBundleId": source.bundleId,
            "grouping": grouping
        ]
        if let name = name {
            result["name"] = name
        }
        if let mealType = mealType {
            result["mealType"] = mealType
        }
        if let energy = values[.energyKcal] {
            result["energyKcal"] = energy
        }
        if let sourceName = source.name {
            result["sourceName"] = sourceName
        }
        return result
    }
}

/// Maps HealthKit food correlations and nutrient samples onto `NutritionEntry`.
enum NutritionMapper {

    struct Nutrient {
        let identifier: HKQuantityTypeIdentifier
        let field: NutritionEntry.Field
        let unit: HKUnit
    }

    /// The nutrients `queryNutrition` reads, and the unit each is normalised to
    /// (kcal for energy, grams for macros) so both platforms return the same number.
    static let nutrients: [Nutrient] = [
        Nutrient(identifier: .dietaryEnergyConsumed, field: .energyKcal, unit: .kilocalorie()),
        Nutrient(identifier: .dietaryProtein, field: .proteinG, unit: .gram()),
        Nutrient(identifier: .dietaryCarbohydrates, field: .carbohydratesG, unit: .gram()),
        Nutrient(identifier: .dietaryFatTotal, field: .fatG, unit: .gram()),
        Nutrient(identifier: .dietaryFatSaturated, field: .saturatedFatG, unit: .gram()),
        Nutrient(identifier: .dietarySugar, field: .sugarG, unit: .gram()),
        Nutrient(identifier: .dietaryFiber, field: .fiberG, unit: .gram())
    ]

    static var quantityTypes: [HKQuantityType] {
        return nutrients.compactMap { HKObjectType.quantityType(forIdentifier: $0.identifier) }
    }

    /// One entry per food correlation. Each nutrient is summed across the
    /// correlation's member samples of that type; a nutrient with no member
    /// sample stays absent. Members of other types (vitamins, caffeine, ...) are ignored.
    static func entry(from correlation: HKCorrelation, source: NutritionSource) -> NutritionEntry {
        var values: [NutritionEntry.Field: Double] = [:]
        for nutrient in nutrients {
            guard let type = HKObjectType.quantityType(forIdentifier: nutrient.identifier) else { continue }
            let samples = correlation.objects(for: type).compactMap { $0 as? HKQuantitySample }
            if !samples.isEmpty {
                values[nutrient.field] = samples.reduce(0) { $0 + $1.quantity.doubleValue(for: nutrient.unit) }
            }
        }

        return NutritionEntry(
            id: correlation.uuid.uuidString,
            startDate: correlation.startDate,
            endDate: correlation.endDate,
            name: correlation.metadata?[HKMetadataKeyFoodType] as? String,
            mealType: mealType(from: correlation.metadata),
            values: values,
            source: source,
            grouping: "correlation"
        )
    }

    /// One entry for a loose nutrient sample, with only that nutrient set.
    /// Returns nil for samples of a type `queryNutrition` does not read.
    static func entry(from sample: HKQuantitySample, source: NutritionSource) -> NutritionEntry? {
        guard let nutrient = nutrients.first(where: { $0.identifier.rawValue == sample.quantityType.identifier }) else {
            return nil
        }

        return NutritionEntry(
            id: sample.uuid.uuidString,
            startDate: sample.startDate,
            endDate: sample.endDate,
            name: sample.metadata?[HKMetadataKeyFoodType] as? String,
            mealType: mealType(from: sample.metadata),
            values: [nutrient.field: sample.quantity.doubleValue(for: nutrient.unit)],
            source: source,
            grouping: "sample"
        )
    }

    /// Drops every sample that is a member of one of the given correlations, so
    /// a nutrient is not counted both inside its correlation and on its own.
    static func ungroupedSamples(_ samples: [HKQuantitySample], excluding correlations: [HKCorrelation]) -> [HKQuantitySample] {
        let grouped = Set(correlations.flatMap { $0.objects.map { $0.uuid } })
        return samples.filter { !grouped.contains($0.uuid) }
    }

    /// Metadata keys some apps use for the meal. HealthKit defines no standard
    /// key, so this is a best-effort list; compared case-insensitively.
    static let mealTypeMetadataKeys: Set<String> = ["meal", "mealtype", "meal_type", "hkfoodmeal"]

    /// Reads a meal type from metadata, or nil when there is no recognisable hint.
    /// Never guesses from the time of day.
    static func mealType(from metadata: [String: Any]?) -> String? {
        guard let metadata = metadata else { return nil }
        for (key, value) in metadata where mealTypeMetadataKeys.contains(key.lowercased()) {
            guard let raw = value as? String else { continue }
            switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
            case "breakfast":
                return "breakfast"
            case "lunch":
                return "lunch"
            case "dinner":
                return "dinner"
            case "snack", "snacks":
                return "snack"
            default:
                continue
            }
        }
        return nil
    }

    /// Sorts by start date (ties by id, for a stable order) and applies the optional limit.
    static func sortAndLimit(_ entries: [NutritionEntry], limit: Int?) -> [NutritionEntry] {
        let sorted = entries.sorted {
            $0.startDate != $1.startDate ? $0.startDate < $1.startDate : $0.id < $1.id
        }
        guard let limit = limit else { return sorted }
        return Array(sorted.prefix(limit))
    }
}
