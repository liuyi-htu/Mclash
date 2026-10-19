package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class RuntimeEditsTest {
    @Test fun runningProxyRejectsEditsBeforeExecutingThem() {
        var changed = false
        try {
            RuntimeEdits.edit({ error("运行中") }) { changed = true }
            fail("Edit should be rejected")
        } catch (_: IllegalStateException) { }
        assertFalse(changed)
    }

    @Test fun startCannotRaceWithAnInFlightSubscriptionUpdate() {
        val editing = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val completed = AtomicBoolean(false)
        val thread = Thread {
            RuntimeEdits.edit({}) {
                editing.countDown()
                check(finish.await(5, TimeUnit.SECONDS))
                completed.set(true)
            }
        }.apply { start() }
        try {
            assertTrue(editing.await(5, TimeUnit.SECONDS))
            var started = false
            try {
                RuntimeEdits.start { started = true }
                fail("Start should be rejected during an edit")
            } catch (_: IllegalStateException) { }
            assertFalse(started)
        } finally {
            finish.countDown()
            thread.join(5000)
        }
        assertTrue(completed.get())
        var started = false
        RuntimeEdits.start { started = true }
        assertTrue(started)
    }

    @Test fun stopCancelsEarlierStartsButNotTheNextExplicitStart() {
        val operations = RootOperationState()
        RuntimeEdits.start { operations.admit(1, false) }
        operations.admit(2, true)
        RuntimeEdits.start { operations.admit(3, false) }
        assertTrue(operations.cancelled(1))
        assertFalse(operations.cancelled(3))
        operations.complete(false)
        assertTrue(operations.starting) // queued start still protects configuration writes
        operations.complete(true)
        assertTrue(operations.starting)
        operations.complete(false)
        assertFalse(operations.starting)
    }

    @Test fun failedEditsReleaseTheStartBlock() {
        try {
            RuntimeEdits.edit({}) { error("Download failed") }
        } catch (_: IllegalStateException) { }
        var started = false
        RuntimeEdits.start { started = true }
        assertTrue(started)
    }
    @Test fun persistedTransitionsSurviveServiceAndAppRecreation() {
        assertEquals("starting", rootProxyStatus("starting", false, false, false))
        assertEquals("stopping", rootProxyStatus("stopping", false, false, false))
        assertEquals("stopping", rootProxyStatus("ready", false, true, true))
        assertEquals("starting", rootProxyStatus("stopped", true, false, false))
        assertEquals("running", rootProxyStatus("cleanup_failed", false, false, true))
        assertEquals("stopped", rootProxyStatus("stopped", false, false, false))
        assertEquals("stopped", rootProxyStatus("stopping", false, false, false, false))
        assertEquals("stopped", rootProxyStatus("stopping", false, false, true, false))
        assertEquals("stopped", rootProxyStatus("ready", false, false, true, false))
        assertEquals("running", rootProxyStatus("ready", false, false, true, true))
        assertEquals("starting", rootProxyStatus("ready", true, false, true, false))
        assertEquals("stopping", rootProxyStatus("ready", false, true, true, false))
    }

}
