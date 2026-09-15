Put the iOS sing-box `Libbox.xcframework` here when you have one.

The current project builds an unsigned IPA without the framework so UI, subscription fetching, AES-GCM decryption, node parsing, delay testing, and Network Extension packaging can be tested first.

To enable a real tunnel:

1. Add `Libbox.xcframework` to this folder.
2. Add it to the `NicecatTunnel` target in `project.yml` or Xcode.
3. Replace the placeholder `startSingBoxTunnel` and `stopSingBoxTunnel` bodies in `NicecatTunnel/PacketTunnelProvider.swift` with the iOS Libbox startup code matching the framework you build.
