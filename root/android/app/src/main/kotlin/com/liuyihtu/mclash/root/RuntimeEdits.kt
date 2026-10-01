package com.liuyihtu.mclash.root

/** Serialize admission, without holding a lock during subscription downloads. */
internal object RuntimeEdits {
    private var activeEdits = 0

    fun <T> edit(requireStopped: () -> Unit, block: () -> T): T {
        synchronized(this) {
            requireStopped()
            activeEdits++
        }
        try {
            return block()
        } finally {
            synchronized(this) { activeEdits-- }
        }
    }

    @Synchronized
    fun start(accept: () -> Unit) {
        check(activeEdits == 0) { "配置正在保存或更新，请完成后再启动代理" }
        accept()
    }
}
