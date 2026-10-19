package com.liuyihtu.mclash

import android.system.Os
import android.system.OsConstants
import java.io.File

/** Used only after Java's force-stop has timed out; never a periodic process scan. */
internal object AndroidProcessTermination {
    internal data class Identity(val pid: Int, val parent: Int, val uid: Int, val startTicks: Long, val command: List<String>)

    internal fun readIdentity(directory: File): Identity? = runCatching {
        val pid = directory.name.toInt()
        val status = File(directory, "status").readLines().associate {
            it.substringBefore(':') to it.substringAfter(':').trim()
        }
        val parent = status.getValue("PPid").toInt()
        val uid = status.getValue("Uid").split(Regex("\\s+")).first().toInt()
        val stat = File(directory, "stat").readText().substringAfterLast(") ").trim().split(Regex("\\s+"))
        val ticks = stat[19].toLong()
        val command = File(directory, "cmdline").readBytes().toString(Charsets.UTF_8)
            .split('\u0000').dropLastWhile { it.isEmpty() }
        Identity(pid, parent, uid, ticks, command)
    }.getOrNull()

    internal fun findOwnedChild(proc: File, parent: Int, uid: Int, command: List<String>): Identity {
        val matches = proc.listFiles().orEmpty().mapNotNull(::readIdentity).filter {
            it.parent == parent && it.uid == uid && it.command == command
        }
        check(matches.size == 1) { "无法唯一确认 mihomo 子进程身份，拒绝发送强制信号" }
        return matches.single()
    }

    fun killOwnedChild(process: Process, command: List<String>) {
        if (!process.isAlive) return
        val identity = findOwnedChild(File("/proc"), android.os.Process.myPid(), android.os.Process.myUid(), command)
        // Recheck ownership, full argv and start time immediately before signalling.
        check(readIdentity(File("/proc/${identity.pid}")) == identity && process.isAlive) {
            "mihomo 子进程身份已变化，拒绝发送强制信号"
        }
        Os.kill(identity.pid, OsConstants.SIGKILL)
    }
}
