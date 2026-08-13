package com.liuyihtu.mclash

import android.content.Context

internal class AppPreferences(context: Context) {
    private val preferences = context.getSharedPreferences("clash", Context.MODE_PRIVATE)

    // Retained for migration from the original single-config implementation.
    var configFileName: String?
        get() = preferences.getString(KEY_CONFIG_FILE_NAME, null)
        set(value) = preferences.edit().putString(KEY_CONFIG_FILE_NAME, value).apply()

    var configProfilesJson: String
        get() = preferences.getString(KEY_CONFIG_PROFILES, "[]") ?: "[]"
        set(value) = preferences.edit().putString(KEY_CONFIG_PROFILES, value).apply()

    var activeConfigId: String?
        get() = preferences.getString(KEY_ACTIVE_CONFIG_ID, null)
        set(value) = preferences.edit().putString(KEY_ACTIVE_CONFIG_ID, value).apply()

    var appProxyMode: String
        get() = when (preferences.getString(KEY_APP_PROXY_MODE, MODE_EXCLUDE)) {
            "onlySelected" -> MODE_INCLUDE
            "excludeSelected" -> MODE_EXCLUDE
            MODE_INCLUDE -> MODE_INCLUDE
            else -> MODE_EXCLUDE
        }
        set(value) = preferences.edit().putString(KEY_APP_PROXY_MODE, value).apply()

    var selectedPackages: Set<String>
        get() = preferences.getStringSet(KEY_SELECTED_PACKAGES, emptySet())?.toSet()
            ?: emptySet()
        set(value) = preferences.edit().putStringSet(KEY_SELECTED_PACKAGES, value).apply()

    var delayTestUrl: String
        get() {
            val stored = preferences.getString(KEY_DELAY_TEST_URL, DEFAULT_DELAY_TEST_URL)
                ?: DEFAULT_DELAY_TEST_URL
            return if (stored in LEGACY_DELAY_TEST_URLS) DEFAULT_DELAY_TEST_URL else stored
        }
        set(value) = preferences.edit().putString(KEY_DELAY_TEST_URL, value).apply()

    var delayResultsJson: String
        get() = preferences.getString(KEY_DELAY_RESULTS_JSON, "{}") ?: "{}"
        set(value) = preferences.edit().putString(KEY_DELAY_RESULTS_JSON, value).apply()

    var acceptedUsageNoticeVersion: Int
        get() = preferences.getInt(KEY_ACCEPTED_USAGE_NOTICE_VERSION, 0)
        set(value) = preferences.edit()
            .putInt(KEY_ACCEPTED_USAGE_NOTICE_VERSION, value)
            .apply()

    var developerModeEnabled: Boolean
        get() = preferences.getBoolean(KEY_DEVELOPER_MODE_ENABLED, false)
        set(value) = preferences.edit().putBoolean(KEY_DEVELOPER_MODE_ENABLED, value).apply()

    var rootAutoStart: Boolean
        get() = preferences.getBoolean(KEY_ROOT_AUTO_START, false)
        set(value) = preferences.edit().putBoolean(KEY_ROOT_AUTO_START, value).apply()

    var rootLoggingEnabled: Boolean
        get() = preferences.getBoolean(KEY_ROOT_LOGGING_ENABLED, false)
        set(value) = preferences.edit().putBoolean(KEY_ROOT_LOGGING_ENABLED, value).apply()

    var rootIpv6Enabled: Boolean
        get() = preferences.getBoolean(KEY_ROOT_IPV6_ENABLED, false)
        set(value) = preferences.edit().putBoolean(KEY_ROOT_IPV6_ENABLED, value).apply()

    var rootBypassLan: Boolean
        get() = preferences.getBoolean(KEY_ROOT_BYPASS_LAN, true)
        set(value) = preferences.edit().putBoolean(KEY_ROOT_BYPASS_LAN, value).apply()

    var rootBypassCidrs: String
        get() = preferences.getString(KEY_ROOT_BYPASS_CIDRS, DEFAULT_ROOT_BYPASS_CIDRS)
            ?: DEFAULT_ROOT_BYPASS_CIDRS
        set(value) = preferences.edit().putString(KEY_ROOT_BYPASS_CIDRS, value).apply()

    var rootProxyMode: String
        get() = preferences.getString(KEY_ROOT_PROXY_MODE, ROOT_PROXY_MODE_TUN)
            ?: ROOT_PROXY_MODE_TUN
        set(value) = preferences.edit().putString(KEY_ROOT_PROXY_MODE, value).apply()

    companion object {
        const val MODE_INCLUDE = "include"
        const val MODE_EXCLUDE = "exclude"
        const val DEFAULT_DELAY_TEST_URL = "http://connect.rom.miui.com/generate_204"
        const val ROOT_PROXY_MODE_TUN = "tun"
        const val ROOT_PROXY_MODE_TPROXY = "tproxy"
        const val DEFAULT_ROOT_BYPASS_CIDRS =
            "10.0.0.0/8\n172.16.0.0/12\n192.168.0.0/16\nfc00::/7\nfe80::/10"

        private val LEGACY_DELAY_TEST_URLS = setOf(
            "http://www.gstatic.com/generate_204",
            "https://www.gstatic.com/generate_204",
        )

        private const val KEY_CONFIG_FILE_NAME = "config_file_name"
        private const val KEY_CONFIG_PROFILES = "config_profiles_json"
        private const val KEY_ACTIVE_CONFIG_ID = "active_config_id"
        private const val KEY_APP_PROXY_MODE = "app_proxy_mode"
        private const val KEY_SELECTED_PACKAGES = "selected_packages"
        private const val KEY_DELAY_TEST_URL = "delay_test_url"
        private const val KEY_DELAY_RESULTS_JSON = "delay_results_json"
        private const val KEY_ACCEPTED_USAGE_NOTICE_VERSION =
            "accepted_usage_notice_version"
        private const val KEY_DEVELOPER_MODE_ENABLED = "developer_mode_enabled"
        private const val KEY_ROOT_AUTO_START = "root_auto_start"
        private const val KEY_ROOT_LOGGING_ENABLED = "root_logging_enabled"
        private const val KEY_ROOT_IPV6_ENABLED = "root_ipv6_enabled"
        private const val KEY_ROOT_BYPASS_LAN = "root_bypass_lan"
        private const val KEY_ROOT_BYPASS_CIDRS = "root_bypass_cidrs"
        private const val KEY_ROOT_PROXY_MODE = "root_proxy_mode"
    }
}
