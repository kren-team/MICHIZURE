package com.kren.michizure.persistence

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first

private val Context.selectedPackageDataStore by preferencesDataStore(
    name = "selected_lock_apps",
)

class SelectedPackageStore(context: Context) {
    private val dataStore = context.selectedPackageDataStore

    suspend fun read(): Set<String> {
        return dataStore.data.first()[selectedPackagesKey].orEmpty().toSet()
    }

    suspend fun save(packageNames: Set<String>) {
        dataStore.edit { preferences ->
            preferences[selectedPackagesKey] = packageNames.toSet()
        }
    }

    companion object {
        private val selectedPackagesKey =
            stringSetPreferencesKey("selected_package_names_v1")
    }
}
