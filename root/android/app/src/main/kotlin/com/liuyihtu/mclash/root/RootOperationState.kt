package com.liuyihtu.mclash.root

import java.util.concurrent.atomic.AtomicInteger

/** Transient operation admission, independent of persistent daemon state. */
internal class RootOperationState(private val starts: AtomicInteger = AtomicInteger()) {
    @Volatile private var stopId = 0
    fun admit(id: Int, stop: Boolean) {
        if (stop) stopId = id else starts.incrementAndGet()
    }
    fun cancelled(id: Int): Boolean = stopId > id
    fun complete(stop: Boolean) { if (!stop) check(starts.decrementAndGet() >= 0) }
    val starting: Boolean get() = starts.get() > 0
}

/** Persistent transitions survive the Android operation service and app process. */
internal fun rootProxyStatus(marker: String?, starting: Boolean, stopping: Boolean, healthy: Boolean, ownerAlive: Boolean? = null): String {
    val phase = marker.takeUnless { ownerAlive == false }
    return when {
        stopping || phase == "stopping" -> "stopping"
        starting || phase == "starting" -> "starting"
        // An orphan core can keep its ports open after the supervisor is killed.
        // A confirmed missing owner must take precedence over that UI hint.
        healthy && ownerAlive != false -> "running"
        else -> "stopped"
    }
}
