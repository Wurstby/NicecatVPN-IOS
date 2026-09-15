# sing-box core integration

The Android app uses `libbox.aar`, which contains Android JNI and `.so` binaries. iOS cannot link that artifact. The iOS project is prepared for the equivalent Apple-side setup:

- Main app fetches and decrypts the subscription.
- Main app parses node links and generates sing-box JSON.
- Main app starts `NETunnelProviderManager`.
- `NicecatTunnel` receives the generated configs and owns the Packet Tunnel lifecycle.
- Real traffic forwarding should be implemented by linking an iOS `Libbox.xcframework` into the `NicecatTunnel` target.

Upstream reference projects:

- sing-box Apple client: https://github.com/SagerNet/sing-box-for-apple
- sing-box documentation: https://sing-box.sagernet.org/
- Apple Network Extension: https://developer.apple.com/documentation/networkextension

## Current project state

Without `Libbox.xcframework`, the extension uses a placeholder tunnel so unsigned CI builds still succeed. This is deliberate: GitHub Actions can then always produce an unsigned IPA for UI/subscription/signing-flow testing.

## Enabling real traffic

1. Build or obtain an iOS `Libbox.xcframework` that supports Packet Tunnel usage.
2. Put it at `ios/NicecatVPN/Vendor/Libbox.xcframework`.
3. Add this dependency to the `NicecatTunnel` target in `project.yml`:

   ```yaml
   dependencies:
     - framework: Vendor/Libbox.xcframework
       embed: false
   ```

4. Replace `startSingBoxTunnel` and `stopSingBoxTunnel` in `NicecatTunnel/PacketTunnelProvider.swift` with the startup/shutdown API used by your `Libbox.xcframework`.

The generated config already includes tun inbound, urltest outbound, rule/global routing, DNS hijack rules, and local `.srs` rule-set paths.
