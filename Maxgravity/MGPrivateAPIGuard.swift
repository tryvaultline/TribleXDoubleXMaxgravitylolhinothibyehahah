// Build configurations must not enable private Apple glass backends.
#if ENABLE_PRIVATE_APPLE_GLASS_BACKENDS
#error("Private Apple glass backends are forbidden in the Maxgravity production target.")
#endif

enum MGPrivateAPIGuard {
    static let shippingConfigurationAllowsPrivateBackends = false
}
