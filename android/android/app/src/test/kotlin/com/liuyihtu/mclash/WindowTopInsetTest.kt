package com.liuyihtu.mclash

import org.junit.Assert.assertEquals
import org.junit.Test

class WindowTopInsetTest {
    @Test fun floatingWindowDoesNotReserveTheScreenStatusBarAgain() {
        assertEquals(0, requiredWindowTopInset(24, 0, 0, 200, 0))
    }
    @Test fun captionAboveNativeContentIsAlreadyHandled() {
        assertEquals(0, requiredWindowTopInset(24, 32, 0, 232, 32))
    }
    @Test fun overlappingCaptionAndCutoutRemainProtected() {
        assertEquals(32, requiredWindowTopInset(24, 32, 0, 200, 0))
        assertEquals(40, requiredWindowTopInset(24, 32, 40, 200, 0))
    }
    @Test fun topSplitScreenStillProtectsVisibleStatusBar() {
        assertEquals(24, requiredWindowTopInset(24, 0, 0, 0, 0))
        assertEquals(0, requiredWindowTopInset(24, 0, 0, 24, 24))
    }
}
