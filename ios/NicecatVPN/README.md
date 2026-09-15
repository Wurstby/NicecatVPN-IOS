# NicecatVPN iOS

这是根据安卓版本移植的 iOS 工程，包含：

- SwiftUI 首页和节点选择页，视觉布局按截图复刻。
- C 语言密钥库，订阅 URL 和 AES key 不直接写在 Swift 业务层。
- AES-GCM 订阅解密，密文格式为 `base64(nonce12 + ciphertext + tag16)`。
- VLESS、VMess、Trojan、Shadowsocks、AnyTLS、Hysteria2、SOCKS、HTTP 节点解析。
- TCP 延迟测试、自动选择最低延迟节点、规则模式/全局模式。
- `NetworkExtension` Packet Tunnel 扩展目标。

## 重要说明

安卓工程使用的是 `libbox.aar/.so`，不能直接用于 iOS。这个项目已经把 iOS 的 VPN 外壳、配置生成、签名权限和扩展目标准备好；当前 `NicecatTunnel` 在没有 iOS 版 `Libbox.xcframework` 时会启动一个不接管默认路由的占位隧道，方便先测试 UI、订阅、测速和个人签名流程。

要实现真实代理流量，需要把 iOS 可用的 sing-box/Libbox 框架接到 `NicecatTunnel/PacketTunnelProvider.swift` 里的 `startSingBoxTunnel` 和 `stopSingBoxTunnel`。

更详细的 sing-box 核心接入说明见 `SINGBOX_CORE.md`。

## GitHub Actions 无签名 IPA

仓库根目录已加入 `.github/workflows/build-ios-unsigned-ipa.yml`。推送到 `main/master` 或手动运行 workflow 后，会输出 `NicecatVPN-unsigned-ipa` artifact。

这个 IPA 是未签名包，普通真机不能直接安装。你需要再用 Xcode、AltStore、Sideloadly、iOS App Signer 或自己的证书脚本重签。重签后是否能启动 Packet Tunnel 取决于你的 Apple 账号是否允许 `packet-tunnel-provider` entitlement。

## 本地个人签名测试

1. 在 macOS 上进入 `ios/NicecatVPN`，运行 `brew install xcodegen && xcodegen generate`。
2. 打开生成的 `NicecatVPN.xcodeproj`。
3. 选中 `NicecatVPN` 和 `NicecatTunnel` 两个 target，把 Team 改成你的 Apple ID 团队。
4. 如果 Bundle ID 被占用，把两个 target 的 Bundle ID 改成你自己的前缀，并保持扩展 ID 是主 App ID 加后缀。
5. 在真机上运行 `NicecatVPN` scheme。

命令行打包 IPA：

```bash
cd ios/NicecatVPN
chmod +x scripts/build_ipa.sh
./scripts/build_ipa.sh
```

生成文件为 `ios/NicecatVPN/build/NicecatVPN-unsigned.ipa`。如果 Xcode 或重签工具报 Network Extension 权限错误，需要在 Apple Developer 账号里给 App ID 开启 Network Extensions / Packet Tunnel capability。
