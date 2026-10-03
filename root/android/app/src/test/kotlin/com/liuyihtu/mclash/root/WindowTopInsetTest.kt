package com.liuyihtu.mclash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WindowTopInsetTest {
    @Test fun floatingWindowHasNoTopPaddingEvenWithAnOverlappingCaption() {
        assertTrue(isFloatingAppWindow(32, 640, 960, 1080, 2400))
        assertTrue(isFloatingAppWindow(0, 640, 960, 1080, 2400))
    }
    @Test fun fullscreenAndSplitScreenAreNotFloatingWindows() {
        assertFalse(isFloatingAppWindow(0, 1080, 2400, 1080, 2400))
        assertFalse(isFloatingAppWindow(0, 1080, 1200, 1080, 2400))
        assertFalse(isFloatingAppWindow(0, 540, 2400, 1080, 2400))
        assertFalse(isFloatingAppWindow(0, 0, 0, 1080, 2400))
    }

    @Test fun floatingBoundsAreDetectedWithoutTheMultiWindowFlag() {
        assertTrue(isCompactAppWindow(false, 0, 640, 960, 1080, 2400))
        assertEquals(0, requiredWindowTopInset(24, 0, 0, 200, 0))
    }
    @Test fun fullscreenAndUnavailableBoundsDoNotEnableTheCorrection() {
        assertFalse(isCompactAppWindow(false, 0, 1080, 2400, 1080, 2400))
        assertFalse(isCompactAppWindow(false, 0, 0, 0, 1080, 2400))
        assertFalse(isCompactAppWindow(false, 0, 1080, 2400, 0, 0))
    }
    @Test fun captionAndSplitScreenAreDetected() {
        assertTrue(isCompactAppWindow(false, 32, 1080, 2400, 1080, 2400))
        assertTrue(isCompactAppWindow(false, 0, 1080, 1200, 1080, 2400))
        assertTrue(isCompactAppWindow(true, 0, 1080, 2400, 1080, 2400))
    }

    @Test fun floatingWindowDoesNotReserveTheScreenStatusBarAgain() {
        assertEquals(0, requiredWindowTopInset(24, 0, 0, 200, 0))
    }
    @Test fun captionAboveNativeContentIsAlreadyHandled() {
        assertEquals(0, requiredWindowTopInset(24, 32, 0, 232, 32))
    }
    @Test fun overlappingCaptionAndCutoutRemainProtected() {
        assertEquals(32, requiredWindowTopInset(24, 32, 0, 200, 0))
        assertEquals(32, requiredWindowTopInset(24, 32, 40, 200, 0))
        assertEquals(40, requiredWindowTopInset(24, 0, 40, 0, 0))
    }
    @Test fun movingBelowTheCutoutRemovesItsOldWhiteSpace() {
        assertEquals(40, requiredWindowTopInset(24, 0, 40, 0, 0))
        assertEquals(0, requiredWindowTopInset(24, 0, 40, 200, 0))
        assertEquals(0, requiredWindowTopInset(24, 0, 40, 40, 0))
    }
    @Test fun topSplitScreenStillProtectsVisibleStatusBar() {
        assertEquals(24, requiredWindowTopInset(24, 0, 0, 0, 0))
        assertEquals(0, requiredWindowTopInset(24, 0, 0, 24, 24))
    }
}
