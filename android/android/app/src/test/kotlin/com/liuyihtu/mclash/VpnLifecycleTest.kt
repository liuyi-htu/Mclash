package com.liuyihtu.mclash

import org.junit.Assert.*
import org.junit.Test

class VpnLifecycleTest {
    @Test fun normalStartStopAndRestart() {
        val state = VpnLifecycle()
        repeat(10) {
            assertTrue(state.requestStart())
            assertEquals(VpnLifecycle.Phase.REQUESTED, state.phase)
            assertTrue(state.beginStart())
            assertTrue(state.finishStart())
            assertEquals(VpnLifecycle.Phase.RUNNING, state.phase)
            state.requestStop()
            state.finishStop(true)
            assertEquals(VpnLifecycle.Phase.STOPPED, state.phase)
        }
    }

    @Test fun duplicateStartDoesNotRestartNativeWork() {
        val state = VpnLifecycle()
        assertTrue(state.requestStart())
        assertFalse(state.requestStart())
        assertTrue(state.beginStart())
        assertFalse(state.beginStart())
        assertFalse(state.requestStart())
        assertTrue(state.finishStart())
        assertFalse(state.finishStart())
        assertFalse(state.requestStart())
    }

    @Test fun stopBeforeServiceStartsCancelsPendingStart() {
        val state = VpnLifecycle()
        state.requestStart()
        state.requestStop()
        assertFalse(state.beginStart())
        assertFalse(state.finishStart())
        state.finishStop(true)
        assertEquals(VpnLifecycle.Phase.STOPPED, state.phase)
    }

    @Test fun stopDuringStartupRejectsLateSuccessAndRestartUntilCleanupCompletes() {
        val state = VpnLifecycle()
        state.beginStart()
        state.requestStop()
        assertFalse(state.finishStart())
        assertThrows(IllegalStateException::class.java) { state.requestStart() }
        state.finishStop(true)
        assertTrue(state.requestStart())
    }

    @Test fun cleanupFailureCannotReportStoppedOrAdmitNewStart() {
        val state = VpnLifecycle()
        state.beginStart()
        state.requestStop()
        state.finishStop(false)
        assertEquals(VpnLifecycle.Phase.STOPPING, state.phase)
        assertFalse(state.finishStart())
        assertThrows(IllegalStateException::class.java) { state.requestStart() }
        state.requestStop() // explicit retry, without an automatic cleanup loop
        state.finishStop(true)
        assertEquals(VpnLifecycle.Phase.STOPPED, state.phase)
    }

    @Test fun duplicateStopAndUnexpectedExitUseSameCleanupState() {
        val state = VpnLifecycle()
        state.beginStart()
        state.finishStart()
        state.requestStop() // component exit
        state.requestStop() // simultaneous user stop
        assertFalse(state.finishStart())
        state.finishStop(true)
        state.finishStop(true)
        assertEquals(VpnLifecycle.Phase.STOPPED, state.phase)
    }

    @Test fun failedStartDeliveryRestoresStoppedButCannotUndoConcurrentStop() {
        val state = VpnLifecycle()
        state.requestStart()
        state.cancelStartRequest()
        assertEquals(VpnLifecycle.Phase.STOPPED, state.phase)
        state.requestStart()
        state.requestStop()
        state.cancelStartRequest()
        assertEquals(VpnLifecycle.Phase.STOPPING, state.phase)
    }

    @Test fun failedStopDeliveryRestoresPendingStartOrRunningState() {
        val state = VpnLifecycle()
        state.requestStart()
        val pending = state.requestStop()
        state.restoreFailedStopDelivery(pending)
        assertEquals(VpnLifecycle.Phase.REQUESTED, state.phase)
        state.beginStart()
        state.finishStart()
        val running = state.requestStop()
        state.restoreFailedStopDelivery(running)
        assertEquals(VpnLifecycle.Phase.RUNNING, state.phase)
    }
    @Test fun failedDeliveryCannotUndoANewerRevocationOrStop() {
        val state = VpnLifecycle()
        state.beginStart()
        state.finishStart()
        val earlier = state.requestStop()
        state.requestStop()
        state.restoreFailedStopDelivery(earlier)
        assertEquals(VpnLifecycle.Phase.STOPPING, state.phase)
    }

    @Test(timeout = 5000) fun concurrentStartAndStopCannotPublishLateRunningState() {
        val pool = java.util.concurrent.Executors.newFixedThreadPool(2)
        try {
            repeat(100) {
                val state = VpnLifecycle()
                val barrier = java.util.concurrent.CyclicBarrier(2)
                val start = pool.submit {
                    barrier.await()
                    runCatching { state.requestStart(); state.beginStart() }
                }
                val stop = pool.submit { barrier.await(); state.requestStop() }
                start.get()
                stop.get()
                assertEquals(VpnLifecycle.Phase.STOPPING, state.phase)
                assertFalse(state.finishStart())
            }
        } finally { pool.shutdownNow() }
    }

    @Test fun oldServiceCleanupCannotCompleteANewerServiceStop() {
        val state = VpnLifecycle()
        state.beginStart()
        state.finishStart()
        val oldService = state.requestStop()
        val newService = state.requestStop()
        state.finishStop(true, oldService)
        assertEquals(VpnLifecycle.Phase.STOPPING, state.phase)
        assertThrows(IllegalStateException::class.java) { state.requestStart() }
        state.finishStop(true, newService)
        assertEquals(VpnLifecycle.Phase.STOPPED, state.phase)
        assertTrue(state.requestStart())
    }

}
