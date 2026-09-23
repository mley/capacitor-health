package com.fit_up.health.capacitor

import androidx.health.connect.client.records.MealType
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Mass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

class NutritionMapperTest {

    private val start = Instant.parse("2026-01-01T12:00:00Z")
    private val end = Instant.parse("2026-01-01T12:30:00Z")

    // Metadata's full constructor is internal, and the public factories leave the
    // data origin empty. Health Connect fills it in on insert.
    private fun metadata(id: String) = Metadata.manualEntryWithId(id)

    private fun record(
        id: String = "record-1",
        startTime: Instant = start,
        endTime: Instant = end,
        energy: Energy? = null,
        protein: Mass? = null,
        totalCarbohydrate: Mass? = null,
        totalFat: Mass? = null,
        saturatedFat: Mass? = null,
        sugar: Mass? = null,
        dietaryFiber: Mass? = null,
        name: String? = null,
        mealType: Int = MealType.MEAL_TYPE_UNKNOWN,
    ) = NutritionRecord(
        startTime = startTime,
        startZoneOffset = ZoneOffset.UTC,
        endTime = endTime,
        endZoneOffset = ZoneOffset.UTC,
        metadata = metadata(id),
        energy = energy,
        protein = protein,
        totalCarbohydrate = totalCarbohydrate,
        totalFat = totalFat,
        saturatedFat = saturatedFat,
        sugar = sugar,
        dietaryFiber = dietaryFiber,
        name = name,
        mealType = mealType,
    )

    @Test
    fun mapsIdentityDatesNameAndSource() {
        val source = record(name = "Porridge")
        val entry = NutritionMapper.fromRecord(source)

        assertEquals("record-1", entry.id)
        assertEquals(start, entry.startDate)
        assertEquals(end, entry.endDate)
        assertEquals("Porridge", entry.name)
        assertEquals(source.metadata.dataOrigin.packageName, entry.sourceBundleId)
        assertEquals("record", entry.grouping)
    }

    @Test
    fun convertsEnergyToKilocalories() {
        val entry = NutritionMapper.fromRecord(record(energy = Energy.kilojoules(418.4)))
        assertEquals(100.0, entry.energyKcal!!, 0.0001)
    }

    @Test
    fun convertsMacrosToGrams() {
        val entry = NutritionMapper.fromRecord(
            record(
                protein = Mass.kilograms(0.025),
                totalCarbohydrate = Mass.milligrams(40_000.0),
                totalFat = Mass.ounces(1.0),
                saturatedFat = Mass.grams(3.0),
                sugar = Mass.grams(12.5),
                dietaryFiber = Mass.micrograms(4_000_000.0),
            )
        )

        assertEquals(25.0, entry.proteinG!!, 0.0001)
        assertEquals(40.0, entry.carbohydratesG!!, 0.0001)
        assertEquals(28.3495, entry.fatG!!, 0.0001)
        assertEquals(3.0, entry.saturatedFatG!!, 0.0001)
        assertEquals(12.5, entry.sugarG!!, 0.0001)
        assertEquals(4.0, entry.fiberG!!, 0.0001)
    }

    /** A nutrient that was not recorded must stay absent - it must not turn into 0. */
    @Test
    fun missingNutrientsStayNull() {
        val entry = NutritionMapper.fromRecord(record(protein = Mass.grams(10.0)))

        assertNull(entry.energyKcal)
        assertNull(entry.carbohydratesG)
        assertNull(entry.fatG)
        assertNull(entry.saturatedFatG)
        assertNull(entry.sugarG)
        assertNull(entry.fiberG)
        assertNull(entry.name)
    }

    /** A recorded zero is real data and must survive as 0, distinct from missing. */
    @Test
    fun recordedZeroIsKept() {
        val entry = NutritionMapper.fromRecord(record(energy = Energy.kilocalories(0.0), sugar = Mass.grams(0.0)))

        assertEquals(0.0, entry.energyKcal!!, 0.0)
        assertEquals(0.0, entry.sugarG!!, 0.0)
    }

    @Test
    fun mapsMealTypes() {
        assertEquals("breakfast", NutritionMapper.mealType(MealType.MEAL_TYPE_BREAKFAST))
        assertEquals("lunch", NutritionMapper.mealType(MealType.MEAL_TYPE_LUNCH))
        assertEquals("dinner", NutritionMapper.mealType(MealType.MEAL_TYPE_DINNER))
        assertEquals("snack", NutritionMapper.mealType(MealType.MEAL_TYPE_SNACK))
        assertEquals("unknown", NutritionMapper.mealType(MealType.MEAL_TYPE_UNKNOWN))
        assertEquals("unknown", NutritionMapper.mealType(42))
    }

    @Test
    fun sortsByStartDateAndAppliesLimit() {
        val late = NutritionMapper.fromRecord(record(id = "late", startTime = end, endTime = end.plusSeconds(60)))
        val early = NutritionMapper.fromRecord(record(id = "early"))
        val alsoEarly = NutritionMapper.fromRecord(record(id = "also-early"))

        val sorted = NutritionMapper.sortAndLimit(listOf(late, early, alsoEarly), null)
        assertEquals(listOf("also-early", "early", "late"), sorted.map { it.id })

        val limited = NutritionMapper.sortAndLimit(listOf(late, early, alsoEarly), 2)
        assertEquals(listOf("also-early", "early"), limited.map { it.id })
    }
}
