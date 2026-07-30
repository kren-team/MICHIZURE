package com.kren.michizure.enforcement

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidPackageCatalogTest {
    @Test
    fun launcherActivitiesAreDeduplicatedByPackageAndKeepLabels() {
        val catalog =
            AndroidPackageCatalog(
                discovery =
                    LaunchableAppDiscovery {
                        listOf(
                            LaunchableApp("social.app", "Social"),
                            LaunchableApp("social.app", "Social secondary"),
                            LaunchableApp("video.app", "Video"),
                        )
                    },
                protectedPackageResolver = ProtectedPackageResolver { emptyMap() },
            )

        val apps = catalog.listLockableApps()

        assertEquals(listOf("social.app", "video.app"), apps.map { it.packageName })
        assertEquals("Social", apps.first().label)
        assertTrue(apps.all { it.isSelectable })
    }

    @Test
    fun demoTargetIsASelectableLauncherCandidate() {
        val catalog =
            AndroidPackageCatalog(
                discovery =
                    LaunchableAppDiscovery {
                        listOf(
                            LaunchableApp(
                                "com.kren.michizure.demotarget",
                                "MICHIZURE Demo SNS",
                            ),
                        )
                    },
                protectedPackageResolver = ProtectedPackageResolver { emptyMap() },
            )

        val target = catalog.listLockableApps().single()

        assertEquals("com.kren.michizure.demotarget", target.packageName)
        assertEquals("MICHIZURE Demo SNS", target.label)
        assertTrue(target.isSelectable)
    }

    @Test
    fun protectedLauncherAndSelfRemainVisibleButDisabled() {
        val catalog =
            AndroidPackageCatalog(
                discovery =
                    LaunchableAppDiscovery {
                        listOf(
                            LaunchableApp("com.kren.michizure", "MICHIZURE"),
                            LaunchableApp("launcher.app", "Launcher"),
                        )
                    },
                protectedPackageResolver =
                    ProtectedPackageResolver {
                        mapOf(
                            "com.kren.michizure" to PackageProtectionReason.SELF,
                            "launcher.app" to PackageProtectionReason.LAUNCHER,
                        )
                    },
            )

        val apps = catalog.listLockableApps()

        assertFalse(apps.single { it.packageName == "com.kren.michizure" }.isSelectable)
        assertFalse(apps.single { it.packageName == "launcher.app" }.isSelectable)
    }

    @Test
    fun emptyLauncherResultStaysEmpty() {
        val catalog =
            AndroidPackageCatalog(
                discovery = LaunchableAppDiscovery { emptyList() },
                protectedPackageResolver = ProtectedPackageResolver { emptyMap() },
            )

        assertTrue(catalog.listLockableApps().isEmpty())
    }

    @Test
    fun discoveryFailureIsNotMisreportedAsAnEmptyCatalog() {
        val catalog =
            AndroidPackageCatalog(
                discovery =
                    LaunchableAppDiscovery {
                        throw IllegalStateException("catalog unavailable")
                    },
                protectedPackageResolver = ProtectedPackageResolver { emptyMap() },
            )

        assertThrows(IllegalStateException::class.java) {
            catalog.listLockableApps()
        }
    }
}
