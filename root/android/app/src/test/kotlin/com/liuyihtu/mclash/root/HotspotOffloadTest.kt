package com.liuyihtu.mclash.root

import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class HotspotOffloadTest {
    private class Fixture : AutoCloseable {
        val dir = Files.createTempDirectory("mclash-offload-").toFile()
        private val bin = File(dir, "bin").apply { mkdirs() }
        init {
            for (iface in listOf("wlan2", "rndis0")) {
                File(dir, "sys/$iface").mkdirs()
                File(dir, "sys/$iface/ifindex").writeText("42\n")
            }
            File(bin, "tc").apply {
                writeText("#!/bin/sh\n" + """
                    action=${'$'}2; iface=${'$'}4
                    case "${'$'}action" in
                     show)
                      [ ! -f ./legacy ] && echo 'filter protocol ipv6 pref 2 bpf handle 0x1 prog_offload_schedcls_tether_upstream6_ether direct-action' || true
                      [ ! -f ./collision ] || echo 'filter protocol all pref 1 bpf handle 0xbeef unrelated-program'
                      [ ! -f ./foreign ] || echo 'filter protocol ip pref 7 u32 chain 0 fh 800: ht divisor 1'
                      [ ! -f "./${'$'}iface.filter" ] || cat "./${'$'}iface.filter"
                      ;;
                     add)
                      echo "add ${'$'}iface" >> ./calls
                      [ ! -f ./fail-add ] || exit 1
                      echo "filter protocol all pref 1 bpf chain 0 handle 0x4d43 direct-action not_in_hw bytecode '1,6 0 0 0'" > "./${'$'}iface.filter"
                      ;;
                     del)
                      echo "del ${'$'}iface" >> ./calls
                      [ ! -f ./fail-delete ] || exit 1
                      rm "./${'$'}iface.filter"
                      ;;
                     *) exit 9;;
                    esac
                """.trimIndent() + "\n")
                setExecutable(true)
            }
        }
        fun run(body: String, code: Int = 0) {
            val script = File(dir, "run.sh").apply {
                writeText("set -eu\n" + HotspotOffload.functions()
                    .replace("/sys/class/net", File(dir, "sys").absolutePath) + body + "\n")
            }
            val builder = ProcessBuilder("/bin/sh", script.absolutePath).directory(dir).redirectErrorStream(true)
            builder.environment()["PATH"] = bin.absolutePath + ":" + System.getenv("PATH")
            val process = builder.start()
            assertTrue(process.waitFor(5, TimeUnit.SECONDS))
            assertEquals(process.inputStream.bufferedReader().readText(), code, process.exitValue())
        }
        fun calls() = File(dir, "calls").takeIf(File::isFile)?.readLines().orEmpty()
        override fun close() { dir.deleteRecursively() }
    }

    @Test fun protectsOnlySelectedInterfaceAndDoesNotRewriteStableState() {
        Fixture().use { f ->
            f.run("ifaces=wlan2; offload_update")
            val journal = File(f.dir, "offload.owned")
            val modified = journal.lastModified()
            f.run("ifaces=wlan2; offload_update")
            assertEquals(listOf("add wlan2"), f.calls())
            assertEquals(modified, journal.lastModified())
            assertFalse(File(f.dir, "rndis0.filter").exists())
            f.run("ifaces=''; offload_update")
            assertEquals(listOf("add wlan2", "del wlan2"), f.calls())
            assertFalse(journal.exists())
        }
    }

    @Test fun refusesForeignPriorityAndDoesNotClaimAnUnjournaledFilter() {
        Fixture().use { f ->
            File(f.dir, "collision").writeText("")
            f.run("ifaces=wlan2; offload_update", 1)
            assertTrue(f.calls().isEmpty())
            assertFalse(File(f.dir, "offload.owned").exists())
            File(f.dir, "collision").delete()
            f.run("ifaces=wlan2; offload_update")
            File(f.dir, "offload.owned").delete()
            f.run("ifaces=wlan2; offload_update", 1)
            f.run("offload_cleanup")
            assertEquals(listOf("add wlan2"), f.calls())
            assertTrue(File(f.dir, "wlan2.filter").exists())
        }
    }

    @Test fun failedCleanupRetainsOwnershipAndInterfaceReuseCannotDeleteForeignState() {
        Fixture().use { f ->
            f.run("ifaces=wlan2; offload_update")
            File(f.dir, "fail-delete").writeText("")
            f.run("offload_cleanup", 1)
            assertTrue(File(f.dir, "offload.owned").exists())
            File(f.dir, "fail-delete").delete()
            f.run("offload_cleanup")
            assertFalse(File(f.dir, "offload.owned").exists())
            f.run("ifaces=wlan2; offload_update")
            File(f.dir, "sys/wlan2/ifindex").writeText("43\n")
            val calls = f.calls()
            f.run("offload_cleanup")
            assertEquals(calls, f.calls())
        }
    }

    @Test fun interruptedInstallationIsRecoverableAndLegacyInterfacesStayUntouched() {
        Fixture().use { f ->
            File(f.dir, "legacy").writeText("")
            f.run("ifaces=wlan2; offload_update")
            assertTrue(f.calls().isEmpty())
            File(f.dir, "legacy").delete()
            File(f.dir, "fail-add").writeText("")
            f.run("ifaces=wlan2; offload_update", 1)
            assertEquals("wlan2 42\n", File(f.dir, "offload.owned").readText())
            f.run("offload_cleanup")
            assertEquals(listOf("add wlan2"), f.calls())
            assertFalse(File(f.dir, "offload.owned").exists())
        }
    }

    @Test fun neverBypassesForeignFiltersEvenWhenTheyAppearAfterInstallation() {
        Fixture().use { f ->
            File(f.dir, "foreign").writeText("")
            f.run("ifaces=wlan2; offload_update", 1)
            assertTrue(f.calls().isEmpty())
            File(f.dir, "foreign").delete()
            f.run("ifaces=wlan2; offload_update")
            File(f.dir, "foreign").writeText("")
            f.run("ifaces=wlan2; offload_update", 1)
            assertEquals(listOf("add wlan2", "del wlan2"), f.calls())
            assertTrue(File(f.dir, "foreign").exists())
            f.run("offload_cleanup")
            assertEquals(listOf("add wlan2", "del wlan2"), f.calls())
        }
    }
}
