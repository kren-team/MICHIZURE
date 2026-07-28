package com.kren.michizure.enforcement

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidPackageCatalogTest {
    @Test
    fun listsLauncherAppsAndDisablesMichizureItself() {
        val context = ApplicationProvider.getApplicationContext<Context>()

        val apps = AndroidPackageCatalog(context).listLockableApps()

        assertTrue(apps.isNotEmpty())
        val self = apps.single { it.packageName == context.packageName }
        assertFalse(self.isSelectable)
        assertTrue(self.protectionReason == PackageProtectionReason.SELF)
    }
}
