package com.liuyihtu.mclash.root

import java.io.File

/** Used only at control boundaries; UI polling never launches su. */
internal object RootProcessIdentity {
    fun functions(): String = """
        proc_stamp() {
            IFS= read -r stat_line < /proc/"${'$'}1"/stat 2>/dev/null || return 1
            stat_tail=${'$'}{stat_line##*) }
            set -- ${'$'}stat_tail
            [ "${'$'}#" -ge 20 ] || return 1
            [ "${'$'}1" != Z ] || return 1
            shift 19
            printf '%s\n' "${'$'}1"
        }
        root_owned() {
            while IFS= read -r status_line; do
                case "${'$'}status_line" in
                    Uid:*) set -- ${'$'}status_line
                        [ "${'$'}2" = 0 ] && [ "${'$'}3" = 0 ] || return 1
                        # mksh's bare return inside a signal trap can preserve the
                        # interrupted wait status. Identity success must be explicit.
                        return 0 ;;
                esac
            done < /proc/"${'$'}1"/status 2>/dev/null
            return 1
        }
        same_process() {
            [ "${'$'}1" -gt 1 ] 2>/dev/null && root_owned "${'$'}1" &&
                [ "${'$'}(proc_stamp "${'$'}1")" = "${'$'}2" ]
        }
    """.trimIndent() + "\n"

    fun supervisor(directory: File, pid: Int, stamp: String): String = functions() + supervisorCheck(directory, pid, stamp)

    fun supervisorCheck(directory: File, pid: Int, stamp: String): String = """
        same_process $pid ${RootShell.quote(stamp)} &&
        [ "${'$'}(readlink /proc/$pid/cwd)" = "${'$'}(readlink -f ${RootShell.quote(directory.absolutePath)})" ] &&
        timeout -s KILL 1 tr '\000' '\n' < /proc/$pid/cmdline | grep -F -x ${RootShell.quote(File(directory, "supervisor.sh").absolutePath)} >/dev/null
    """.trimIndent()
}
