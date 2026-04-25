package com.inkbridge.data.settings

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/**
 * Unit tests for [SettingsRepository].
 *
 * Uses a minimal in-memory fake [android.content.SharedPreferences] so the test
 * runs on the JVM with no Android instrumentation.
 */
class SettingsRepositoryTest {
    private lateinit var prefs: FakeSharedPreferences
    private lateinit var repo: SettingsRepository

    @BeforeEach
    fun setUp() {
        prefs = FakeSharedPreferences()
        repo = SettingsRepository(prefs)
    }

    @Test
    fun `naturalScroll defaults to true when no key stored`() {
        assertTrue(repo.naturalScroll)
    }

    @Test
    fun `setting naturalScroll to false persists and reads back false`() {
        repo.naturalScroll = false
        assertFalse(repo.naturalScroll)
    }

    @Test
    fun `setting naturalScroll to true after false reads back true`() {
        repo.naturalScroll = false
        repo.naturalScroll = true
        assertTrue(repo.naturalScroll)
    }

    @Test
    fun `writes use the correct SharedPreferences key`() {
        repo.naturalScroll = false
        assertFalse(prefs.getBoolean(SettingsRepository.KEY_NATURAL_SCROLL, true))
    }
}
