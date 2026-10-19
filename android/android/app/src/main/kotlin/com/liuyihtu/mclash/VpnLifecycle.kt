package com.liuyihtu.mclash

/** Admission/state only; native work remains on ProxyVpnService's serial worker. */
internal class VpnLifecycle {
    enum class Phase { STOPPED, REQUESTED, STARTING, RUNNING, STOPPING }

    data class StopRequest(val previous: Phase, val revision: Long)
    private var stopRevision = 0L

    @Volatile
    var phase = Phase.STOPPED
        private set

    @Synchronized
    fun requestStart(): Boolean {
        check(phase != Phase.STOPPING) { "代理正在停止，请稍后再启动" }
        if (phase != Phase.STOPPED) return false
        phase = Phase.REQUESTED
        return true
    }

    @Synchronized
    fun beginStart(): Boolean {
        if (phase != Phase.STOPPED && phase != Phase.REQUESTED) return false
        phase = Phase.STARTING
        return true
    }

    @Synchronized
    fun cancelStartRequest() {
        if (phase == Phase.REQUESTED) phase = Phase.STOPPED
    }

    @Synchronized
    fun finishStart(): Boolean {
        if (phase != Phase.STARTING) return false
        phase = Phase.RUNNING
        return true
    }

    @Synchronized
    fun requestStop(): StopRequest {
        val request = StopRequest(phase, ++stopRevision)
        phase = Phase.STOPPING
        return request
    }

    @Synchronized
    fun restoreFailedStopDelivery(request: StopRequest) {
        if (phase == Phase.STOPPING && stopRevision == request.revision) phase = request.previous
    }

    @Synchronized
    fun finishStop(success: Boolean, request: StopRequest? = null) {
        if (request != null && request.revision != stopRevision) return
        if (phase == Phase.STOPPING && success) phase = Phase.STOPPED
    }
}
