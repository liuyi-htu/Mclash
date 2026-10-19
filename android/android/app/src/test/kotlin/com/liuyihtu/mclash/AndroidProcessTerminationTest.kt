package com.liuyihtu.mclash

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class AndroidProcessTerminationTest {
    private val command = listOf("/data/app/test/libmihomo.so", "-d", "/data/user/0/test/files/mihomo", "-f", "runtime.yaml")
    private fun child(root: File, pid: Int, parent: Int = 100, uid: Int = 10401, args: List<String> = command): File {
        val directory = File(root, "$pid").apply { mkdirs() }
        File(directory, "status").writeText("Name:\tlibmihomo\nPPid:\t$parent\nUid:\t$uid $uid $uid $uid\n")
        val fields = MutableList(20) { "0" }.apply { this[0] = "S"; this[1] = "$parent"; this[19] = "123456" }
        File(directory, "stat").writeText("$pid (name with ) spaces) " + fields.joinToString(" "))
        File(directory, "cmdline").writeText(args.joinToString("\u0000", postfix = "\u0000"))
        return directory
    }
    private fun fixture(block: (File) -> Unit) {
        val root = Files.createTempDirectory("owned-mihomo").toFile()
        try { block(root) } finally { root.deleteRecursively() }
    }
    @Test fun selectsOnlyExactOwnedChildAndParsesStatWithParentheses() = fixture { root ->
        child(root, 201); child(root, 202, uid = 0); child(root, 203, parent = 999)
        child(root, 204, args = command + "extra")
        val found = AndroidProcessTermination.findOwnedChild(root, 100, 10401, command)
        assertEquals(201, found.pid); assertEquals(123456L, found.startTicks)
    }
    @Test fun missingOrUnrelatedChildrenCannotBeSignalled() = fixture { root ->
        child(root, 201, args = listOf("/system/bin/sleep", "60"))
        assertThrows(IllegalStateException::class.java) { AndroidProcessTermination.findOwnedChild(root, 100, 10401, command) }
    }
    @Test fun ambiguousOwnedCommandsMustFailClosed() = fixture { root ->
        child(root, 201); child(root, 202)
        assertThrows(IllegalStateException::class.java) { AndroidProcessTermination.findOwnedChild(root, 100, 10401, command) }
    }
    @Test fun vanishedOrMalformedProcEntryIsIgnored() = fixture { root ->
        val vanished = child(root, 201); File(vanished, "stat").delete()
        assertNull(AndroidProcessTermination.readIdentity(vanished))
        child(root, 202)
        assertEquals(202, AndroidProcessTermination.findOwnedChild(root, 100, 10401, command).pid)
    }
}
