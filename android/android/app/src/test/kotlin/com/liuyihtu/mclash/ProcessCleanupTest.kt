package com.liuyihtu.mclash

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class ProcessCleanupTest {
    private class Child(var alive: Boolean = true, val graceful: Boolean = true, val forceWorks: Boolean = true) : Process() {
        val calls = mutableListOf<String>()
        var failClose = false
        val output = object : ByteArrayInputStream(byteArrayOf()) {
            override fun close() { calls += "close-output"; if (failClose) throw IOException("closed badly") }
        }
        val errors = object : ByteArrayInputStream(byteArrayOf()) {
            override fun close() { calls += "close-errors" }
        }
        val input = object : ByteArrayOutputStream() {
            override fun close() { calls += "close-input" }
        }
        override fun getInputStream() = output
        override fun getErrorStream() = errors
        override fun getOutputStream() = input
        override fun isAlive() = alive
        override fun destroy() { calls += "term"; if (graceful) alive = false }
        override fun destroyForcibly(): Process { calls += "kill"; if (forceWorks) alive = false; return this }
        override fun waitFor(timeout: Long, unit: TimeUnit): Boolean { calls += "wait-$timeout"; return !alive }
        override fun waitFor() = exitValue()
        override fun exitValue(): Int { check(!alive); return 0 }
    }

    @Test fun normalStopReapsThenClosesAllPipes() {
        val child = Child()
        ProcessCleanup.terminate(child)
        assertEquals(listOf("term", "wait-3", "close-output", "close-errors", "close-input"), child.calls)
    }
    @Test fun unresponsiveChildGetsBoundedForceStop() {
        val child = Child(graceful = false)
        ProcessCleanup.terminate(child)
        assertEquals(listOf("term", "wait-3", "kill", "wait-2", "close-output", "close-errors", "close-input"), child.calls)
    }
    @Test fun forceTimeoutDoesNotReleaseAliveChildOrReportSuccess() {
        val child = Child(graceful = false, forceWorks = false)
        assertThrows(IllegalStateException::class.java) { ProcessCleanup.terminate(child) }
        assertTrue(child.alive)
        assertEquals(listOf("term", "wait-3", "kill", "wait-2"), child.calls)
    }
    @Test fun alreadyExitedChildStillClosesItsPipes() {
        val child = Child(alive = false)
        ProcessCleanup.terminate(child)
        assertEquals(listOf("close-output", "close-errors", "close-input"), child.calls)
    }
    @Test fun validatorTimeoutUsesImmediateForceStop() {
        val child = Child()
        ProcessCleanup.terminate(child, gracefulSeconds = 0)
        assertEquals(listOf("kill", "wait-2", "close-output", "close-errors", "close-input"), child.calls)
    }
    @Test fun oneBadPipeCannotSkipOtherPipeClosures() {
        val child = Child(alive = false).apply { failClose = true }
        assertThrows(IllegalStateException::class.java) { ProcessCleanup.terminate(child) }
        assertEquals(listOf("close-output", "close-errors", "close-input"), child.calls)
    }
    @Test fun androidFallbackRunsOnlyAfterJavaForceHasTimedOut() {
        val child = Child(graceful = false, forceWorks = false)
        ProcessCleanup.terminate(child, forceFallback = { child.calls += "verified-sigkill"; child.alive = false })
        assertEquals(listOf("term", "wait-3", "kill", "wait-2", "verified-sigkill", "wait-2", "close-output", "close-errors", "close-input"), child.calls)
    }
    @Test fun failedIdentityCheckDoesNotCloseAliveChildPipes() {
        val child = Child(graceful = false, forceWorks = false)
        assertThrows(IllegalStateException::class.java) {
            ProcessCleanup.terminate(child, forceFallback = { error("identity mismatch") })
        }
        assertTrue(child.alive)
        assertFalse(child.calls.any { it.startsWith("close-") })
    }
    @Test fun successfulJavaForceDoesNotScanOrSignalOtherProcesses() {
        val child = Child(graceful = false)
        ProcessCleanup.terminate(child, forceFallback = { error("must not run") })
        assertFalse(child.alive)
    }

}
