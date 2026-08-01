package com.kren.michizure.persistence

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SelectedPackageStoreTest {
    @Test
    fun persistsAndRestoresSelectedPackages() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val firstStore = SelectedPackageStore(context)
        val expected = setOf("demo.social", "demo.video")
        val original = firstStore.read()

        try {
            firstStore.save(expected)

            assertEquals(expected, SelectedPackageStore(context).read())
        } finally {
            firstStore.save(original)
        }
    }
}
