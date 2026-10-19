package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit

class RootSupervisorTest {
    /** Only the host harness substitutes UID and readiness; production requires UID 0. */
    private class Fixture(val failCleanup: Boolean = false, val coreFails: Boolean = false, val dyingCmdlineStalls: Boolean = false) : AutoCloseable {
        val dir = Files.createTempDirectory("root-supervisor-test-").toFile()
        private val uid = ProcessBuilder("id", "-u").start().inputStream.bufferedReader().readText().trim()
        val core = File(dir, "libmihomo.so").apply {
            writeText("#!/usr/bin/python3\nimport signal,time,sys\n" +
                if (coreFails) "time.sleep(.2)\nsys.exit(9)\n"
                else if (dyingCmdlineStalls) "def stop(*_):\n open('stop-began','w').close()\n time.sleep(.3)\n sys.exit(0)\nsignal.signal(signal.SIGTERM,stop)\nsignal.pause()\n"
                else "signal.pause()\n")
            setExecutable(true)
        }
        val process: Process
        init {
            File(dir, "runtime.yaml").writeText("mode: rule")
            File(dir, "sharing.policy").writeText("0\n")
            File(dir, "cleanup.sh").writeText("echo cleanup >> ./cleanup.calls\n" + if (failCleanup) "[ -f ./allow-cleanup ]\n" else "exit 0\n")
            File(dir, "install.sh").writeText("echo installed > ./installed\n")
            File(dir, "hotspot-monitor.sh").writeText("echo apply >> ./sharing.calls\ncp ./sharing.policy ./sharing.applied\n")
            File(dir, "sharing-watch.sh").writeText(RootSupervisor.sharingWatcher().replace("/system/bin/sh", "/bin/sh")
                .replace("[ \"${'$'}2\" = 0 ] && [ \"${'$'}3\" = 0 ]", "[ \"${'$'}2\" = $uid ] && [ \"${'$'}3\" = $uid ]"))
            File(dir, "log-writer.sh").writeText(RootSupervisor.logWriter().replace("/system/bin/sh", "/bin/sh"))
            File(dir, "log-maintenance.sh").writeText(DebugLogLimits.maintenanceScript())
            var script = RootSupervisor.script(dir, core, uid.toInt(), false, false)
                .replace("/system/bin/sh", "/bin/sh")
                .replace("[ \"${'$'}(id -u)\" = 0 ]", "[ \"${'$'}(id -u)\" = $uid ]")
                .replace("[ \"${'$'}2\" = 0 ] && [ \"${'$'}3\" = 0 ]", "[ \"${'$'}2\" = $uid ] && [ \"${'$'}3\" = $uid ]")
                .replace("listener_ready() {", "unused_listener_ready() {")
                .replace("sleep \"${'$'}backoff\"", ":")
            script = "listener_ready() { return ${if (coreFails) 1 else 0}; }\n" + script
            val file = File(dir, "supervisor.sh").apply { writeText(script) }
            val builder = ProcessBuilder("/bin/sh", file.absolutePath).directory(dir)
                .redirectErrorStream(true).redirectOutput(File(dir, "output"))
            if (dyingCmdlineStalls) {
                val bin = File(dir, "bin").apply { mkdirs() }
                File(bin, "tr").apply {
                    writeText("#!/bin/sh\nif [ -f ./stop-began ]; then sleep 30; fi\nexec /usr/bin/tr \"${'$'}@\"\n")
                    setExecutable(true)
                }
                builder.environment()["PATH"] = bin.absolutePath + ":" + System.getenv("PATH")
            }
            process = builder.start()
        }
        fun awaitState(value: String) {
            val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(12)
            while (System.nanoTime() < until) {
                if (File(dir, "ready").takeIf { it.isFile }?.readText()?.trim() == value) return
                Thread.sleep(20)
            }
            fail("Expected $value: " + File(dir, "output").readText())
        }
        fun pid(): String = File(dir, "supervisor.pid").readText().trim()
        fun signal(value: String) {
            assertEquals(0, ProcessBuilder("kill", "-$value", pid()).start().waitFor())
        }
        fun awaitExit() {
            assertTrue(File(dir, "output").readText(), process.waitFor(12, TimeUnit.SECONDS))
            val pid = File(dir, "core.pid").readText().trim()
            val args = runCatching { File("/proc/$pid/cmdline").readText() }.getOrDefault("")
            assertFalse("A stopped marker must not hide a live owned core", args.contains(core.absolutePath))
        }
        override fun close() {
            if (process.isAlive) { process.destroy(); if (!process.waitFor(12, TimeUnit.SECONDS)) process.destroyForcibly() }
            File(dir, "core.pid").takeIf { it.isFile }?.readText()?.trim()?.let { pid ->
                val args = File("/proc/$pid/cmdline")
                if (args.isFile && runCatching { args.readText().contains(core.absolutePath) }.getOrDefault(false)) {
                    ProcessBuilder("kill", "-KILL", pid).start().waitFor()
                }
            }
            dir.deleteRecursively()
        }
    }

    @Test fun idleOwnerBlocksWithoutPeriodicSharingCallsAndStopsBySignal() {
        Fixture().use { f ->
            f.awaitState("ready")
            val before = File(f.dir, "sharing.calls").readText()
            val children = File("/proc/${f.pid()}/task/${f.pid()}/children").readText().trim().split(" ").filter { it.isNotBlank() }
            assertEquals(2, children.size) // core + blocked log reader, no hotspot worker
            Thread.sleep(2300)
            assertEquals(before, File(f.dir, "sharing.calls").readText())
            assertTrue(f.process.isAlive)
            f.signal("TERM")
            f.awaitExit()
            f.awaitState("stopped")
            assertEquals(listOf("cleanup"), File(f.dir, "cleanup.calls").readLines())
        }
    }

    @Test fun stoppingDoesNotReadTheCommandLineOfAnExitingChild() {
        Fixture(dyingCmdlineStalls = true).use { f ->
            f.awaitState("ready")
            val before = System.nanoTime()
            f.signal("TERM"); f.awaitExit(); f.awaitState("stopped")
            assertTrue(File(f.dir, "stop-began").isFile)
            assertTrue("Dying /proc reads must not stall cleanup", System.nanoTime() - before < TimeUnit.SECONDS.toNanos(5))
        }
    }

    @Test fun coreCrashTriggersCleanupWithoutAnAndroidService() {
        Fixture().use { f ->
            f.awaitState("ready")
            val pid = File(f.dir, "core.pid").readText().trim()
            assertEquals(0, ProcessBuilder("kill", "-KILL", pid).start().waitFor())
            f.awaitExit()
            f.awaitState("stopped")
            assertTrue(File(f.dir, "cleanup.calls").isFile)
        }
    }

    @Test fun cleanupFailureIsBoundedAndExplicit() {
        Fixture(failCleanup = true).use { f ->
            f.awaitState("ready")
            f.signal("TERM")
            f.awaitState("cleanup_failed")
            assertTrue(f.process.isAlive)
            assertEquals(4, File(f.dir, "cleanup.calls").readLines().size)
            Thread.sleep(500)
            assertEquals(4, File(f.dir, "cleanup.calls").readLines().size)
            File(f.dir, "allow-cleanup").writeText("retry")
            f.signal("TERM"); f.awaitExit(); f.awaitState("stopped")
            assertEquals(5, File(f.dir, "cleanup.calls").readLines().size)
        }
    }

    @Test fun sharingControlInterruptsWaitAndReturnsToSleep() {
        Fixture().use { f ->
            f.awaitState("ready")
            // A stop arriving after acknowledgement but before a slow update
            // returns must be drained, rather than lost before the next wait.
            File(f.dir, "hotspot-monitor.sh").appendText("sleep .4\n")
            File(f.dir, "sharing.policy").writeText("0\nwlan2\n")
            f.signal("USR1")
            val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (File(f.dir, "sharing.applied").readText() != "0\nwlan2\n" && System.nanoTime() < until) Thread.sleep(20)
            assertEquals("0\nwlan2\n", File(f.dir, "sharing.applied").readText())
            assertEquals(2, File(f.dir, "sharing.calls").readLines().size)
            assertTrue(f.process.isAlive)
            f.signal("TERM"); f.awaitExit(); f.awaitState("stopped")
        }
    }

    @Test fun startupFailureStillRollsBackWithoutInstallingRules() {
        Fixture(coreFails = true).use { f ->
            f.awaitExit(); f.awaitState("stopped")
            assertFalse(File(f.dir, "installed").exists())
            assertEquals(1, File(f.dir, "cleanup.calls").readLines().size)
        }
    }

    @Test fun selectedSharingStartsAnEventWorkerAndDisablingStopsIt() {
        Fixture().use { f ->
            f.awaitState("ready")
            File(f.dir, "sharing.policy").writeText("1\nwlan2\n")
            f.signal("USR1")
            val identity = File(f.dir, "sharing.identity")
            val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (!identity.isFile && System.nanoTime() < until) Thread.sleep(20)
            assertTrue(File(f.dir, "output").readText(), identity.isFile)
            val worker = identity.readText().trim().split(" ").first()
            assertTrue(File("/proc/$worker").isDirectory)
            File(f.dir, "sharing.policy").writeText("0\nwlan2\n")
            f.signal("USR1")
            val stopped = System.nanoTime() + TimeUnit.SECONDS.toNanos(8)
            while (File(f.dir, "sharing.applied").readText() != "0\nwlan2\n" && System.nanoTime() < stopped) Thread.sleep(20)
            assertEquals("0\nwlan2\n", File(f.dir, "sharing.applied").readText())
            assertFalse(File("/proc/$worker").isDirectory)
            f.signal("TERM"); f.awaitExit(); f.awaitState("stopped")
        }
    }

    @Test fun rootIdentitySuccessIsExplicitInsideAnInterruptedWaitTrap() {
        val dir = Files.createTempDirectory("identity-trap-").toFile()
        try {
            val proc = File(dir, "123").apply { mkdirs() }
            File(proc, "stat").writeText("123 (sh) S 1 " + "0 ".repeat(17) + "777 0\n")
            File(proc, "status").writeText("Uid:\t0\t0\t0\t0\n")
            val functions = RootProcessIdentity.functions().replace("/proc/", dir.absolutePath + "/")
            val script = functions + "\ntrap 'same_process 123 777 && echo matched > " +
                RootShell.quote(File(dir, "matched").absolutePath) + "' USR1\n" +
                "(sleep .1; kill -USR1 \"${'$'}${'$'}\") &\nwait \"${'$'}!\" || true\n"
            val process = ProcessBuilder("/bin/sh", "-c", script).start()
            assertTrue(process.waitFor(3, TimeUnit.SECONDS))
            assertTrue(File(dir, "matched").isFile)
        } finally { dir.deleteRecursively() }
    }

    @Test fun processIdentityParsesNamesWithSpacesAndRejectsUidOrStampChanges() {
        val dir = Files.createTempDirectory("identity-fixture").toFile()
        try {
            val proc = File(dir, "123").apply { mkdirs() }
            File(proc, "stat").writeText("123 (name with spaces) S 1 " + "0 ".repeat(17) + "777 0\n")
            File(proc, "status").writeText("Uid:\t0\t0\t0\t0\n")
            fun run(stamp: String): Int {
                val script = RootProcessIdentity.functions().replace("/proc/", dir.absolutePath + "/") + "\nsame_process 123 $stamp"
                return ProcessBuilder("/bin/sh", "-c", script).start().waitFor()
            }
            assertEquals(0, run("777"))
            assertNotEquals(0, run("778"))
            File(proc, "status").writeText("Uid:\t1000\t1000\t1000\t1000\n")
            assertNotEquals(0, run("777"))
        } finally { dir.deleteRecursively() }
    }
    @Test fun supervisorIdentityAcceptsPhysicalDirectoryAliasButRejectsWrongCommand() {
        val dir = Files.createTempDirectory("supervisor-identity-").toFile()
        try {
            val home = File(dir, "physical").apply { mkdirs() }
            val alias = File(dir, "alias")
            Files.createSymbolicLink(alias.toPath(), home.toPath())
            val proc = File(dir, "proc/123").apply { mkdirs() }
            File(proc, "stat").writeText("123 (sh) S 1 " + "0 ".repeat(17) + "777 0\n")
            File(proc, "status").writeText("Uid:\t0\t0\t0\t0\n")
            Files.createSymbolicLink(File(proc, "cwd").toPath(), home.toPath())
            val args = File(proc, "cmdline")
            args.writeText("/system/bin/sh\u0000" + File(alias, "supervisor.sh").absolutePath + "\u0000")
            fun check(stamp: String): Int {
                val script = RootProcessIdentity.supervisor(alias, 123, stamp)
                    .replace("/proc/", File(dir, "proc").absolutePath + "/")
                return ProcessBuilder("/bin/sh", "-c", "if $script; then exit 0; else exit 1; fi").start().waitFor()
            }
            assertEquals(0, check("777"))
            assertNotEquals(0, check("778"))
            args.writeText("/system/bin/sh\u0000unrelated.sh\u0000")
            assertNotEquals(0, check("777"))
        } finally { dir.deleteRecursively() }
    }

}
