package hev.htproxy

import androidx.annotation.Keep

/**
 * JNI entry points supplied by libhev-socks5-tunnel.so.
 *
 * The native library registers these methods by their exact names and
 * signatures during JNI_OnLoad. They must never be removed or renamed by R8.
 */
@Keep
object TProxyService {
    init {
        System.loadLibrary("hev-socks5-tunnel")
    }

    @Volatile
    var onExit: ((Int) -> Unit)? = null

    @Keep
    @JvmStatic
    fun tunnelExited(code: Int) {
        onExit?.invoke(code)
    }

    @Keep
    external fun TProxyStartService(configPath: String, fd: Int): Boolean

    @Keep
    external fun TProxyStopService(): Boolean

    @Keep
    external fun TProxyIsRunning(): Boolean

    @Keep
    external fun TProxyGetStats(): LongArray
}
