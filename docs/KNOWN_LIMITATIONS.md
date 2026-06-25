# Known Limitations

- Official Antigravity CLI / SDK task control has not been verified. Maxgravity must not claim live task mirroring until a documented machine interface is confirmed.
- The bridge does not expose itself publicly and does not implement a cloud relay.
- Desktop trust confirmation UI is not implemented yet.
- iOS Keychain persistence is not wired end-to-end yet.
- Windows DPAPI helpers exist, but production secret persistence still needs desktop integration.
- Local screenshots cannot be captured from this Windows host because Xcode simulator tooling is unavailable.
- Background Live Activity updates require Apple Developer configuration, APNs credentials, and physical-device testing.
- The unsigned IPA is not App Store signed. Sideloading requires user-supplied Apple credentials in Sideloadly or equivalent tooling.
