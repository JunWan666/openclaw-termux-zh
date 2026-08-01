package com.junwan666.openclawzh

import org.junit.Assert.assertEquals
import org.junit.Test

class RootfsTransactionPolicyTest {
    @Test
    fun `upgrade interruption restores rollback in every transaction phase`() {
        listOf("extracting", "activating", "verifying").forEach { phase ->
            assertEquals(
                RootfsRecoveryAction.RESTORE_ROLLBACK,
                RootfsTransactionPolicy.recoveryAction(
                    phase = phase,
                    hadCurrentRootfs = true,
                    rollbackExists = true,
                ),
            )
        }
    }

    @Test
    fun `staging interruption keeps an existing committed rootfs`() {
        assertEquals(
            RootfsRecoveryAction.KEEP_CURRENT_ROOTFS,
            RootfsTransactionPolicy.recoveryAction(
                phase = "extracting",
                hadCurrentRootfs = true,
                rollbackExists = false,
            ),
        )
    }

    @Test
    fun `fresh install activation failure deletes uncommitted rootfs`() {
        listOf("activating", "verifying").forEach { phase ->
            assertEquals(
                RootfsRecoveryAction.DELETE_UNCOMMITTED_ROOTFS,
                RootfsTransactionPolicy.recoveryAction(
                    phase = phase,
                    hadCurrentRootfs = false,
                    rollbackExists = false,
                ),
            )
        }
    }

    @Test
    fun `fresh install extraction interruption does not delete an unrelated rootfs`() {
        assertEquals(
            RootfsRecoveryAction.KEEP_CURRENT_ROOTFS,
            RootfsTransactionPolicy.recoveryAction(
                phase = "extracting",
                hadCurrentRootfs = false,
                rollbackExists = false,
            ),
        )
    }

    @Test
    fun `legacy or unreadable lock defaults to preserving current rootfs`() {
        assertEquals(
            RootfsRecoveryAction.KEEP_CURRENT_ROOTFS,
            RootfsTransactionPolicy.recoveryAction(
                phase = null,
                hadCurrentRootfs = true,
                rollbackExists = false,
            ),
        )
    }
}
