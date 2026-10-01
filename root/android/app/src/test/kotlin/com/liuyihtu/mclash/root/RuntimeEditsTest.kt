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

    @Test fun failedEditsReleaseTheStartBlock() {
        try {
            RuntimeEdits.edit({}) { error("Download failed") }
        } catch (_: IllegalStateException) { }
        var started = false
        RuntimeEdits.start { started = true }
        assertTrue(started)
    }
}
