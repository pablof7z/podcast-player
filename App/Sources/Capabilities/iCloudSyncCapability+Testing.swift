import Foundation

#if DEBUG
extension iCloudSyncCapability {
    /// Test-only seam: drive the capability into the started state
    /// without a `KernelModel`. The outbound path checks `started` but
    /// not `kernel`, so this enables outbound-only unit tests that do
    /// not need a live Rust kernel handle. Compiled out of release
    /// builds.
    func testForceStarted() {
        started = true
    }

    /// Test-only seam: directly flip the echo-suppression flag so the
    /// outbound-skip behaviour can be exercised without round-tripping
    /// through an external KVS notification.
    func testSetApplyingRemoteChange(_ value: Bool) {
        isApplyingRemoteChange = value
    }
}
#endif
