package com.junwan666.openclawzh

internal enum class RootfsRecoveryAction {
    RESTORE_ROLLBACK,
    DELETE_UNCOMMITTED_ROOTFS,
    KEEP_CURRENT_ROOTFS,
}

internal object RootfsTransactionPolicy {
    fun recoveryAction(
        phase: String?,
        hadCurrentRootfs: Boolean,
        rollbackExists: Boolean,
    ): RootfsRecoveryAction {
        if (rollbackExists) return RootfsRecoveryAction.RESTORE_ROLLBACK

        val activationMayHaveCompleted = phase == "activating" || phase == "verifying"
        return if (!hadCurrentRootfs && activationMayHaveCompleted) {
            RootfsRecoveryAction.DELETE_UNCOMMITTED_ROOTFS
        } else {
            RootfsRecoveryAction.KEEP_CURRENT_ROOTFS
        }
    }
}
