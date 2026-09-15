The iOS sing-box `Libbox.xcframework` is generated here by `scripts/build_libbox_ios.sh`.

The framework is intentionally ignored by git because it is large and platform-specific. GitHub Actions rebuilds it before running XcodeGen, then links it into the `NicecatTunnel` Network Extension.
