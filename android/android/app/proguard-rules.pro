# HevSocks5Tunnel registers these methods with RegisterNatives by exact name.
-keep class hev.htproxy.TProxyService {
    <fields>;
    <methods>;
}

-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep the Android VPN service and Flutter activity entry points.
-keep class com.liuyihtu.mclash.ProxyVpnService { *; }
-keep class com.liuyihtu.mclash.MainActivity { *; }


