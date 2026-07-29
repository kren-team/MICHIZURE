package com.kren.michizure.monitoring

data class SystemFlowLease(
    val flowType: String,
    val expectedPackages: Set<String>,
    val issuedElapsedMs: Long,
    val expiresElapsedMs: Long,
    val singleUse: Boolean = true,
) {
    init {
        require(flowType.isNotBlank())
        require(expectedPackages.isNotEmpty())
        require(expectedPackages.none(String::isBlank))
        require(expiresElapsedMs >= issuedElapsedMs)
    }
}

class SystemFlowLeaseRegistry {
    private var activeLease: SystemFlowLease? = null

    fun issue(lease: SystemFlowLease) {
        activeLease = lease
    }

    fun clear() {
        activeLease = null
    }

    fun consumes(packageName: String, nowElapsedMs: Long): Boolean {
        val lease = activeLease ?: return false
        if (nowElapsedMs < lease.issuedElapsedMs ||
            nowElapsedMs > lease.expiresElapsedMs ||
            packageName !in lease.expectedPackages
        ) {
            if (nowElapsedMs > lease.expiresElapsedMs) {
                activeLease = null
            }
            return false
        }
        if (lease.singleUse) {
            activeLease = null
        }
        return true
    }
}
