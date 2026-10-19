package com.liuyihtu.mclash.root

import java.io.File

/** Small shell owner: blocks in wait; only explicit controls interrupt the wait. */
internal object RootSupervisor {
    const val PROTOCOL = "2"

    fun script(directory: File, core: File, appUid: Int, tun: Boolean, ipv6: Boolean): String {
        val home = RootShell.quote(directory.absolutePath)
        return """
            #!/system/bin/sh
            set -eu
            umask 077
            cd $home
            [ "${'$'}(id -u)" = 0 ] || exit 1
            ${RootProcessIdentity.functions()}
            # Break the Android UID process-group/freezer dependency before any fork.
            # Root managers differ in cgroup version and mount point. Fail closed if
            # still in the app's group; setsid alone is not sufficient.
            if grep -qE '/uid_$appUid(/|${'$'})' /proc/self/cgroup; then
                for tasks in /sys/fs/cgroup/cgroup.procs /dev/freezer/cgroup.procs /dev/freezer/tasks /sys/fs/cgroup/freezer/tasks /acct/cgroup.procs; do
                    [ ! -w "${'$'}tasks" ] || { echo ${'$'}${'$'} > "${'$'}tasks"; } 2>/dev/null || true
                done
                ! grep -qE '/uid_$appUid(/|${'$'})' /proc/self/cgroup || { echo '无法脱离应用进程组，拒绝后台启动'; exit 1; }
            fi
            cleanup_rules=${'$'}(cat ./cleanup.sh)
            mkdir ./daemon.lock || { echo 'Root supervisor lock is held'; exit 1; }
            core_pid=''; core_stamp=''; sharing_pid=''; logger_pid=''
            control_pending=0; stop_requested=0; phase_ready=0; control_busy=1; cleaned=0
            publish() {
                printf '%s\n' "${'$'}1" > ./ready.tmp
                chown $appUid:$appUid ./ready.tmp
                mv -f ./ready.tmp ./ready
            }
            stop_child() {
                child=${'$'}1; stamp=${'$'}2; expected=${'$'}3; group=${'$'}{4:-0}
                [ -n "${'$'}child" ] || return 0
                matches_child() {
                    same_process "${'$'}child" "${'$'}stamp" || return 1
                    # Direct-child identity also covers the brief fork-before-exec
                    # window (including a logger waiting to open its FIFO).
                    IFS= read -r child_stat < /proc/"${'$'}child"/stat || return 1
                    child_tail=${'$'}{child_stat##*) }; set -- ${'$'}child_tail
                    [ "${'$'}2" = "${'$'}${'$'}" ] || return 1
                    child_args=${'$'}(timeout -s KILL 1 tr '\000' '\n' < /proc/"${'$'}child"/cmdline) || return 1
                    printf '%s\n' "${'$'}child_args" | grep -F -x -e "${'$'}expected" -e ${RootShell.quote(File(directory, "supervisor.sh").absolutePath)} >/dev/null
                }
                if matches_child; then
                    target=${'$'}child
                    [ "${'$'}group" = 0 ] || target=-${'$'}child
                    kill -TERM "${'$'}target" 2>/dev/null || true
                    # After signalling, only compare the captured UID/start tick.
                    # Reading a dying Android process's cmdline can stall in tr.
                    n=0
                    while same_process "${'$'}child" "${'$'}stamp" && [ "${'$'}n" -lt 30 ]; do
                        sleep 0.1; n=${'$'}((n + 1))
                    done
                    ! same_process "${'$'}child" "${'$'}stamp" || kill -KILL "${'$'}target" 2>/dev/null || true
                    wait "${'$'}child" 2>/dev/null || true
                fi
            }
            stop_sharing() {
                if [ -n "${'$'}sharing_pid" ]; then
                    stop_child "${'$'}sharing_pid" "${'$'}sharing_stamp" ./sharing-watch.sh 1
                    sharing_pid=''
                fi
            }
            apply_sharing() {
                stop_sharing
                timeout -s KILL 20 /system/bin/sh ./hotspot-monitor.sh || return 1
                IFS= read -r enabled < ./sharing.policy || enabled=0
                selected=${'$'}(sed '1d' ./sharing.policy)
                if [ "${'$'}enabled" = 1 ] && [ -n "${'$'}selected" ]; then
                    setsid /system/bin/sh ./sharing-watch.sh >> ./supervisor.log 2>&1 &
                    sharing_pid=${'$'}!; sharing_stamp=${'$'}(proc_stamp "${'$'}sharing_pid")
                    printf '%s %s\n' "${'$'}sharing_pid" "${'$'}sharing_stamp" > ./sharing.identity.tmp
                    mv ./sharing.identity.tmp ./sharing.identity
                fi
            }
            cleanup_routes() {
                cleaned=0
                for backoff in 0 1 2 4; do
                    [ "${'$'}backoff" = 0 ] || sleep "${'$'}backoff"
                    if timeout -s KILL 10 /system/bin/sh -c "${'$'}cleanup_rules"; then cleaned=1; return 0; fi
                done
                return 1
            }
            cleanup() {
                trap - EXIT
                trap '' HUP INT TERM USR1
                publish stopping || true
                stop_sharing
                if [ "${'$'}cleaned" != 1 ]; then cleanup_routes || true; fi
                stop_child "${'$'}core_pid" "${'$'}core_stamp" ${RootShell.quote(core.absolutePath)}
                if [ -n "${'$'}logger_pid" ]; then stop_child "${'$'}logger_pid" "${'$'}logger_stamp" ./log-writer.sh; fi
                rm -f ./log.pipe
                rmdir ./daemon.lock || true
                if [ "${'$'}cleaned" = 1 ]; then publish stopped; else publish cleanup_failed; fi
            }
            dispatch_controls() {
                [ "${'$'}phase_ready" = 1 ] && [ "${'$'}control_busy" = 0 ] || return 0
                control_busy=1
                while [ "${'$'}control_pending" = 1 ] || [ "${'$'}stop_requested" = 1 ]; do
                    control_pending=0
                    if [ "${'$'}stop_requested" = 1 ]; then
                        stop_requested=0
                        stop_sharing
                        publish stopping
                        if cleanup_routes; then exit 0; fi
                        publish cleanup_failed
                        core_alive || exit 1
                    else
                        apply_sharing || { echo '共享策略应用失败'; exit 1; }
                    fi
                done
                control_busy=0
                # A signal during the last loop test may have queued work while
                # busy. Drain it before returning; idle signals dispatch directly.
                if [ "${'$'}control_pending" = 1 ] || [ "${'$'}stop_requested" = 1 ]; then dispatch_controls; fi
            }
            request_stop() {
                [ "${'$'}phase_ready" = 1 ] || exit 0
                stop_requested=1; control_pending=1
                dispatch_controls
            }
            request_sharing() { control_pending=1; dispatch_controls; }
            trap cleanup EXIT
            trap request_stop HUP INT TERM
            trap request_sharing USR1
            echo ${'$'}${'$'} > ./supervisor.pid.tmp
            proc_stamp ${'$'}${'$'} > ./supervisor.stamp.tmp
            chown $appUid:$appUid ./supervisor.pid.tmp ./supervisor.stamp.tmp
            mv ./supervisor.pid.tmp ./supervisor.pid
            mv ./supervisor.stamp.tmp ./supervisor.stamp
            publish starting
            ${if (tun) "! ip link show dev mclash0 >/dev/null 2>&1 || { echo 'mclash0 接口已占用'; exit 1; }" else ""}
            rm -f ./log.pipe
            mkfifo ./log.pipe
            /system/bin/sh ./log-writer.sh < ./log.pipe &
            logger_pid=${'$'}!; logger_stamp=${'$'}(proc_stamp "${'$'}logger_pid")
            printf '%s %s\n' "${'$'}logger_pid" "${'$'}logger_stamp" > ./logger.identity.tmp
            mv ./logger.identity.tmp ./logger.identity
            ${RootShell.quote(core.absolutePath)} -d $home -f ${RootShell.quote(File(directory, "runtime.yaml").absolutePath)} > ./log.pipe 2>&1 &
            core_pid=${'$'}!; core_stamp=${'$'}(proc_stamp "${'$'}core_pid")
            echo "${'$'}core_pid" > ./core.pid
            echo "${'$'}core_stamp" > ./core.stamp
            chown $appUid:$appUid ./core.pid ./core.stamp
            owner_alive() { return 0; }
            core_alive() { same_process "${'$'}core_pid" "${'$'}core_stamp"; }
            listener_ready() {
                ${if (tun) "ip link show dev mclash0 >/dev/null 2>&1" else "awk '${'$'}2 ~ /:45E2${'$'}/ && ${'$'}4 == \"0A\" {found=1} END {exit !found}' /proc/net/tcp /proc/net/tcp6"} &&
                awk '${'$'}2 ~ /:2382${'$'}/ && ${'$'}4 == "0A" {found=1} END {exit !found}' /proc/net/tcp /proc/net/tcp6
            }
            n=0
            while ! listener_ready; do
                core_alive || { echo '启动期间内核退出'; exit 1; }
                [ "${'$'}n" -lt 900 ] || { echo '等待内核监听超时'; exit 1; }
                sleep 0.1; n=${'$'}((n + 1))
            done
            echo ready > ./ports-ready
            ${if (ipv6 && !tun) MihomoProcess.ipv6ListenerCheck() else ""}
            ${if (tun) "echo 0 > /proc/sys/net/ipv4/conf/mclash0/rp_filter" else ""}
            timeout 30 /system/bin/sh ./install.sh
            apply_sharing
            phase_ready=1
            publish ready
            echo 'TPROXY_READY'
            control_busy=0
            dispatch_controls
            while :; do
                # No sleep or process probes in standby. Controls are dispatched
                # by traps, even if they arrive immediately before entering wait.
                if wait "${'$'}core_pid"; then core_exit=0; else core_exit=${'$'}?; fi
                if ! core_alive; then
                    echo "Mihomo exited: ${'$'}core_exit"
                    exit "${'$'}core_exit"
                fi
                dispatch_controls
            done
        """.trimIndent() + "\n"
    }

    /** No worker at all when disabled; netlink plus a sharing-only 60s fallback. */
    fun sharingWatcher(): String = RootProcessIdentity.functions() + """
        set -eu
        umask 077
        ip_pid=''; fallback_pid=''
        cleanup_watch() {
            trap - EXIT HUP INT TERM
            [ -z "${'$'}ip_pid" ] || kill "${'$'}ip_pid" 2>/dev/null || true
            [ -z "${'$'}fallback_pid" ] || kill "${'$'}fallback_pid" 2>/dev/null || true
            [ -z "${'$'}ip_pid" ] || wait "${'$'}ip_pid" 2>/dev/null || true
            [ -z "${'$'}fallback_pid" ] || wait "${'$'}fallback_pid" 2>/dev/null || true
            rm -f ./sharing.events
        }
        trap cleanup_watch EXIT
        trap 'exit 0' HUP INT TERM
        rm -f ./sharing.events
        mkfifo ./sharing.events
        exec 3<> ./sharing.events
        ip monitor link address route >&3 2>/dev/null &
        ip_pid=${'$'}!
        (
            sleeper=''
            trap '[ -z "${'$'}sleeper" ] || kill "${'$'}sleeper" 2>/dev/null || true; exit 0' HUP INT TERM
            while :; do
                sleep 60 & sleeper=${'$'}!
                wait "${'$'}sleeper" || exit 0
                printf 'fallback\n' >&3
            done
        ) &
        fallback_pid=${'$'}!
        IFS= read -r owner_pid < ./supervisor.pid
        IFS= read -r owner_stamp < ./supervisor.stamp
        while IFS= read -r event <&3; do
            same_process "${'$'}owner_pid" "${'$'}owner_stamp" || exit 0
            timeout -s KILL 20 /system/bin/sh ./hotspot-monitor.sh || echo '共享监控更新失败，将在下次事件或兜底检查重试'
        done
    """.trimIndent() + "\n"

    fun orphanHelper(directory: File, role: String): String {
        require(role in setOf("sharing", "logger"))
        return RootProcessIdentity.functions() + """
        set -eu
        cd ${RootShell.quote(directory.absolutePath)}
        for role in ${RootShell.quote(role)}; do
            [ -r "./${'$'}role.identity" ] || continue
            IFS=' ' read -r pid stamp < "./${'$'}role.identity" || continue
            case "${'$'}role" in sharing) expected=./sharing-watch.sh;; logger) expected=./log-writer.sh;; esac
            owned_helper() {
                same_process "${'$'}pid" "${'$'}stamp" &&
                [ "${'$'}(readlink /proc/"${'$'}pid"/cwd)" = "${'$'}(readlink -f ${RootShell.quote(directory.absolutePath)})" ] &&
                timeout -s KILL 1 tr '\000' '\n' < /proc/"${'$'}pid"/cmdline | grep -F -x "${'$'}expected" >/dev/null
            }
            owned_helper || continue
            target=${'$'}pid
            if [ "${'$'}role" = sharing ]; then
                IFS= read -r stat_line < /proc/"${'$'}pid"/stat
                stat_tail=${'$'}{stat_line##*) }; set -- ${'$'}stat_tail
                [ "${'$'}4" = "${'$'}pid" ] || { echo '共享监控会话身份不符'; exit 1; }
                target=-${'$'}pid
            fi
            kill -TERM "${'$'}target" 2>/dev/null || true
            n=0
            while same_process "${'$'}pid" "${'$'}stamp" && [ "${'$'}n" -lt 30 ]; do sleep .1; n=${'$'}((n + 1)); done
            ! same_process "${'$'}pid" "${'$'}stamp" || kill -KILL "${'$'}target" 2>/dev/null || true
            n=0
            while same_process "${'$'}pid" "${'$'}stamp" && [ "${'$'}n" -lt 20 ]; do sleep .1; n=${'$'}((n + 1)); done
            ! same_process "${'$'}pid" "${'$'}stamp" || { echo '无法停止残留监控进程'; exit 1; }
        done
    """.trimIndent() + "\n"

    }

    /** Blocks on the core's pipe; rotation is triggered by bytes written, not time. */
    fun logWriter(): String = """
        set -eu
        LC_ALL=C; export LC_ALL
        bytes=0
        while IFS= read -r line || [ -n "${'$'}line" ]; do
            printf '%s\n' "${'$'}line" >> ./mihomo.log
            bytes=${'$'}((bytes + ${'$'}{#line} + 1))
            if [ "${'$'}bytes" -gt ${DebugLogLimits.MAX_BYTES} ]; then
                /system/bin/sh ./log-maintenance.sh
                bytes=${DebugLogLimits.KEEP_BYTES}
            fi
        done
    """.trimIndent() + "\n"
}
