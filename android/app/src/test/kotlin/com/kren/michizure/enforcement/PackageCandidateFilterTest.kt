package com.kren.michizure.enforcement

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PackageCandidateFilterTest {
    private val filter = PackageCandidateFilter()

    @Test
    fun excludesNonLaunchableComponentsAndDeduplicatesPackages() {
        val apps =
            filter.filter(
                listOf(
                    PackageCandidate("video.app", "Video", true),
                    PackageCandidate("video.app", "Video duplicate", true),
                    PackageCandidate("android.systemui", "System UI", false),
                ),
            )

        assertEquals(listOf("video.app"), apps.map { it.packageName })
    }

    @Test
    fun keepsUserFacingSystemAppsUnlessAndroidMarksThemProtected() {
        val apps =
            filter.filter(
                listOf(
                    PackageCandidate("youtube.app", "YouTube", true),
                    PackageCandidate(
                        "launcher.app",
                        "Launcher",
                        true,
                        PackageProtectionReason.LAUNCHER,
                    ),
                ),
            )

        assertTrue(apps.single { it.packageName == "youtube.app" }.isSelectable)
        val launcher = apps.single { it.packageName == "launcher.app" }
        assertFalse(launcher.isSelectable)
        assertEquals(PackageProtectionReason.LAUNCHER, launcher.protectionReason)
    }

    @Test
    fun ownAppAndCriticalRolesAreDisabledWithTypedReasons() {
        val apps =
            filter.filter(
                listOf(
                    PackageCandidate(
                        "com.kren.michizure",
                        "MICHIZURE",
                        true,
                        PackageProtectionReason.SELF,
                    ),
                    PackageCandidate(
                        "dialer.app",
                        "Phone",
                        true,
                        PackageProtectionReason.DIALER,
                    ),
                    PackageCandidate(
                        "settings.app",
                        "Settings",
                        true,
                        PackageProtectionReason.SETTINGS,
                    ),
                ),
            )

        assertTrue(apps.all { !it.isSelectable })
        assertEquals(
            setOf(
                PackageProtectionReason.SELF,
                PackageProtectionReason.DIALER,
                PackageProtectionReason.SETTINGS,
            ),
            apps.mapNotNull { it.protectionReason }.toSet(),
        )
    }
}
