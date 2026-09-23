package com.fit_up.health.capacitor

import androidx.health.connect.client.records.MealType
import androidx.health.connect.client.records.NutritionRecord
import java.time.Instant

/**
 * One `queryNutrition` entry, before it is serialized to JS.
 *
 * Kept free of Capacitor/Android types so the mapping can be unit tested on the
 * JVM. Nutrient fields are null when the source did not record them - they are
 * omitted from the JS result, never reported as 0.
 */
data class NutritionEntry(
    val id: String,
    val startDate: Instant,
    val endDate: Instant,
    val name: String?,
    val mealType: String,
    val energyKcal: Double?,
    val proteinG: Double?,
    val carbohydratesG: Double?,
    val fatG: Double?,
    val saturatedFatG: Double?,
    val sugarG: Double?,
    val fiberG: Double?,
    val sourceBundleId: String,
) {
    // Health Connect has no food correlations, every record is one entry.
    val grouping: String get() = "record"
}

object NutritionMapper {

    fun fromRecord(record: NutritionRecord) = NutritionEntry(
        id = record.metadata.id,
        startDate = record.startTime,
        endDate = record.endTime,
        name = record.name,
        mealType = mealType(record.mealType),
        energyKcal = record.energy?.inKilocalories,
        proteinG = record.protein?.inGrams,
        carbohydratesG = record.totalCarbohydrate?.inGrams,
        fatG = record.totalFat?.inGrams,
        saturatedFatG = record.saturatedFat?.inGrams,
        sugarG = record.sugar?.inGrams,
        fiberG = record.dietaryFiber?.inGrams,
        sourceBundleId = record.metadata.dataOrigin.packageName,
    )

    fun mealType(value: Int): String = when (value) {
        MealType.MEAL_TYPE_BREAKFAST -> "breakfast"
        MealType.MEAL_TYPE_LUNCH -> "lunch"
        MealType.MEAL_TYPE_DINNER -> "dinner"
        MealType.MEAL_TYPE_SNACK -> "snack"
        else -> "unknown"
    }

    /** Sorts by start date (ties by id, for a stable order) and applies the optional limit. */
    fun sortAndLimit(entries: List<NutritionEntry>, limit: Int?): List<NutritionEntry> {
        val sorted = entries.sortedWith(compareBy<NutritionEntry>({ it.startDate }, { it.id }))
        return if (limit == null) sorted else sorted.take(limit)
    }
}
