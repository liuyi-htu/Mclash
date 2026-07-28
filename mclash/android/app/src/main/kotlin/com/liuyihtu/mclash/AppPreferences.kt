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
        get() = preferences.getString(KEY_APP_PROXY_MODE, MODE_EXCLUDE_SELECTED)
            ?: MODE_EXCLUDE_SELECTED
        set(value) = preferences.edit().putString(KEY_APP_PROXY_MODE, value).apply()

    var selectedPackages: Set<String>
        get() = preferences.getStringSet(KEY_SELECTED_PACKAGES, emptySet())?.toSet()
            ?: emptySet()
        set(value) = preferences.edit().putStringSet(KEY_SELECTED_PACKAGES, value).apply()

    var debugLoggingEnabled: Boolean
        get() = preferences.getBoolean(KEY_DEBUG_LOGGING_ENABLED, false)
        set(value) = preferences.edit().putBoolean(KEY_DEBUG_LOGGING_ENABLED, value).apply()

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

    var vpnMtu: Int
        get() = preferences.getInt(KEY_VPN_MTU, DEFAULT_VPN_MTU)
        set(value) = preferences.edit().putInt(KEY_VPN_MTU, value).apply()

    var tcpBufferSize: Int
        get() = preferences.getInt(KEY_TCP_BUFFER_SIZE, DEFAULT_TCP_BUFFER_SIZE)
        set(value) = preferences.edit().putInt(KEY_TCP_BUFFER_SIZE, value).apply()

    var vpnIpv4DnsServers: List<String>
        get() = readDnsServers(KEY_VPN_IPV4_DNS_SERVERS) ?: run {
            val legacy = readDnsServers(KEY_VPN_DNS_SERVERS)
            legacy
                ?.filterNot { ':' in it }
                ?.takeIf { it.isNotEmpty() }
                ?: DEFAULT_VPN_IPV4_DNS_SERVERS
        }
        set(value) = preferences.edit()
            .putString(KEY_VPN_IPV4_DNS_SERVERS, value.joinToString(","))
            .apply()

    var vpnBypassLan: Boolean
        get() = preferences.getBoolean(KEY_VPN_BYPASS_LAN, DEFAULT_VPN_BYPASS_LAN)
        set(value) = preferences.edit().putBoolean(KEY_VPN_BYPASS_LAN, value).apply()

    var acceptedUsageNoticeVersion: Int
        get() = preferences.getInt(KEY_ACCEPTED_USAGE_NOTICE_VERSION, 0)
        set(value) = preferences.edit()
            .putInt(KEY_ACCEPTED_USAGE_NOTICE_VERSION, value)
            .apply()

    var developerModeEnabled: Boolean
        get() = preferences.getBoolean(KEY_DEVELOPER_MODE_ENABLED, false)
        set(value) = preferences.edit().putBoolean(KEY_DEVELOPER_MODE_ENABLED, value).apply()

    companion object {
        const val MODE_ONLY_SELECTED = "onlySelected"
        const val MODE_EXCLUDE_SELECTED = "excludeSelected"
        const val DEFAULT_DELAY_TEST_URL = "http://connect.rom.miui.com/generate_204"
        const val DEFAULT_VPN_MTU = 1500
        const val DEFAULT_TCP_BUFFER_SIZE = 262144
        val DEFAULT_VPN_IPV4_DNS_SERVERS = listOf("1.1.1.1")
        const val DEFAULT_VPN_BYPASS_LAN = true

        private val LEGACY_DELAY_TEST_URLS = setOf(
            "http://www.gstatic.com/generate_204",
            "https://www.gstatic.com/generate_204",
        )

        private const val KEY_CONFIG_FILE_NAME = "config_file_name"
        private const val KEY_CONFIG_PROFILES = "config_profiles_json"
        private const val KEY_ACTIVE_CONFIG_ID = "active_config_id"
        private const val KEY_APP_PROXY_MODE = "app_proxy_mode"
        private const val KEY_SELECTED_PACKAGES = "selected_packages"
        private const val KEY_DEBUG_LOGGING_ENABLED = "debug_logging_enabled"
        private const val KEY_DELAY_TEST_URL = "delay_test_url"
        private const val KEY_DELAY_RESULTS_JSON = "delay_results_json"
        private const val KEY_VPN_MTU = "vpn_mtu"
        private const val KEY_TCP_BUFFER_SIZE = "tcp_buffer_size"
        // Kept to migrate IPv4 entries from the original shared DNS setting.
        private const val KEY_VPN_DNS_SERVERS = "vpn_dns_servers"
        private const val KEY_VPN_IPV4_DNS_SERVERS = "vpn_ipv4_dns_servers"
        private const val KEY_VPN_BYPASS_LAN = "vpn_bypass_lan"
        private const val KEY_ACCEPTED_USAGE_NOTICE_VERSION =
            "accepted_usage_notice_version"
        private const val KEY_DEVELOPER_MODE_ENABLED = "developer_mode_enabled"
    }

    private fun readDnsServers(key: String): List<String>? =
        preferences.getString(key, null)
            ?.split(',')
            ?.map(String::trim)
            ?.filter(String::isNotEmpty)
}
