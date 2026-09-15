# sing-box core integration

The Android app uses `libbox.aar`, which contains Android JNI and `.so` binaries. iOS cannot link that artifact. The iOS project now builds an iOS `Libbox.xcframework` from the official sing-box source and links it into the `NicecatTunnel` Packet Tunnel extension.

- Main app fetches and decrypts the subscription.
- Main app parses node links and generates sing-box JSON.
- Main app starts `NETunnelProviderManager`.
- `NicecatTunnel` receives the selected config as `configContent` and owns the Packet Tunnel lifecycle.
- The extension starts sing-box with `LibboxNewCommandServer` and `startOrReloadService`.
- The iOS platform bridge opens the Network Extension TUN file descriptor for sing-box.

Upstream reference projects:

- sing-box: https://github.com/SagerNet/sing-box
- sing-box Apple client: https://github.com/SagerNet/sing-box-for-apple
- sing-box documentation: https://sing-box.sagernet.org/
- Apple Network Extension: https://developer.apple.com/documentation/networkextension

## Building the core

`scripts/build_libbox_ios.sh` pins sing-box to `v1.14.1` by default:

```bash
cd ios/NicecatVPN
./scripts/build_libbox_ios.sh
```

Override the source tag when needed:

```bash
SING_BOX_REF=v1.14.1 ./scripts/build_libbox_ios.sh
```

Then build the unsigned IPA:

```bash
cd ios/NicecatVPN
./scripts/build_ipa.sh
```

The generated config includes tun inbound, urltest outbound, rule/global routing, DNS hijack rules, local `.srs` rule-set paths, and `route.auto_detect_interface` to avoid routing loops.

## iOS signing note

The unsigned IPA can be produced in CI, but installing on a physical iPhone still requires re-signing with a certificate/provisioning profile that includes the Packet Tunnel Network Extension entitlement.
