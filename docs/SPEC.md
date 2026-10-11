# EdgeWake 规格

## Context
用户有 MacBook Pro（M2，macOS 27）和放在左侧的 Mac mini（同一 Apple ID，24h 运行）。两台之间用 Apple 通用控制。Mac mini 显示器关闭后（例如锁屏界面按 ESC），通用控制会断开，指针过不去。锁屏本身不影响通用控制。已验证用 `ssh … 'caffeinate -u -t 2'` 点亮对端显示器后，通用控制会自动恢复。

目标：在 `~/code/EdgeWake` 新建一个 Swift 菜单栏 App，两台 Mac 都安装。App 负责两件事：引导用户把两台 Mac 的相关设置配好；把指针连续撞向边缘时，自动点亮对端显示器。整个过程不需要 SSH、不需要 sudo，也不需要输入系统密码。

## 产品规格

**定位**：通用小工具，第一版保证两台 Mac 场景。暂不推送 GitHub；以后开源用 MIT 许可证，GitHub 只放源码，不发布构建产物。界面支持英文和简体中文，最低 macOS 15。

**架构**：两端安装同一个 App，彼此对称。
- 发现：Bonjour `_edgewake._tcp`，用 `NWListener` 和 `NWBrowser` 实现。
- 通信：TCP 长连接，消息加密。
- 被唤醒端用 `IOPMAssertionDeclareUserActivity(kIOPMUserActiveLocal)` 点亮自己的显示器，效果等同于 `caffeinate -u`。
- 每台 Mac 监听 `NSWorkspace.screensDidSleep` 和 `screensDidWake` 通知，把自己显示器的亮灭状态实时推送给对端。

**配对**：一台 Mac 显示 6 位码，有效期 2 分钟，在另一台 Mac 上输入，只需配对一次。
- 密码学构造全部用 CryptoKit 重新编写，不拷贝 unictrl 的代码，因为那部分版权归 Enliva LLC，许可证是 GPL‑3.0。
- 流程：P‑256 ECDH 交换密钥；用配对码作为密钥，对双方公钥做 HMAC，作为持有配对码的证明；HKDF 派生长期密钥。
- 会话密钥 = HKDF(长期密钥, 双方各自生成的 nonce)。消息用 AES‑GCM 加密，nonce 采用计数器以防重放。
- 长期密钥存在钥匙串（Keychain）中。

**消息类型**：`hello/auth`、`status`（显示器状态、检查项结果、App 版本）、`wake`、`wakeAck`、`pointerEntered(edge, t)`。

**触发方式**：
1. **撞边手势**，以下条件全部满足才触发：
   - 对端在线，并且对端上报“显示器已灭”。
   - 撞的是“对端所在侧”的外边缘，两块屏之间的内边缘不算。如果还没学到对端方位，左右两条外边缘都算。
   - 600ms 内撞边 2 次。指针要先离开边缘至少 8px，再回来撞，才算新的一次。
   - 撞边时没有按住任何鼠标键。
   - 当前前台不是全屏应用。
   - 距上次唤醒已超过 10 秒；收到 `wakeAck` 后立即开始计算这 10 秒。
   - 撞边次数和时间窗口在设置里可调。
2. **菜单栏**「立即唤醒」。
3. **全局快捷键**，默认 ⌃⌥⌘W，可修改，按下后唤醒全部已配对的对端。快捷键注册用 Carbon `RegisterEventHotKey`。

**反馈**：触发后在指针附近显示一个小提示，例如「正在唤醒 Mac mini…」，收到 `wakeAck` 或超时后消失。对端离线时提示「Mac mini 离线」，不发系统通知，也不等待。

**对端方位**：首次设置时由用户点选“对端在左侧还是右侧”，之后根据实际穿越自动校正。
- 判定依据：本机指针在 t 时刻从某一外边缘消失，对端在约 500ms 内上报 `pointerEntered(相反边缘)`。
- 发现与设置不一致时自动更新，并发一条系统通知告知用户。

**引导（合并清单）**：首次启动弹出引导窗口；之后可以从设置里再次打开。窗口里同时显示两台 Mac 的检查结果。
- 可自动检测：Wi‑Fi 已开、蓝牙已开、接力已开、系统不会自动睡眠。最后一项不满足时只给提示，不做网络唤醒。
- 需用户自行确认（配图示）：两台 Mac 登录同一 Apple ID；「显示器 › 高级」里通用控制的 3 个开关。
- 未通过的检查项提供深链接按钮，打开对应的系统设置页。若是对端的检查项，就让对端屏幕弹出跳转提示。
- 不修改任何私有配置。

**界面形态**：只显示菜单栏图标，不显示 Dock 图标，图标颜色表示状态：全部正常、有对端屏幕已灭、有检查项未通过。菜单内容：每个对端的在线和亮灭状态、「立即唤醒」、「设置…」。默认登录时自动启动，通过 `SMAppService.mainApp` 实现。

**不做**：模拟关屏、网络唤醒（WoL）、SSH 通道、写入私有配置、发布 GitHub Release。

## 技术决策与仓库结构
- 构建：只用 SwiftPM，不建 Xcode 工程，执行目标为 `EdgeWake`，测试目标为 `EdgeWakeTests`。
- 打包：`scripts/build-app.sh` 组装 `.app` 并签名，`scripts/make-dmg.sh` 用 `hdiutil` 生成 dmg。
- 签名：用 Xcode Personal Team 的免费 Apple Development 证书。证书有效期约一年；本 App 没有受限的 entitlements，所以不需要描述文件（provisioning profile），也就没有“7 天过期”的问题。前面关于 7 天的说法是描述文件的限制，在这里不适用。
- Bundle ID：`io.github.elity.EdgeWake`。
- 依赖：快捷键录制 UI 用 `sindresorhus/KeyboardShortcuts`（MIT），其余全部用系统框架。
- Info.plist：`LSUIElement`、`NSBonjourServices`、`NSLocalNetworkUsageDescription`。

目录结构：
```
~/code/EdgeWake/
  Package.swift  Info.plist  README.md  LICENSE(MIT)  docs/SPEC.md
  scripts/build-app.sh  scripts/make-dmg.sh
  Sources/EdgeWake/
    App/        EdgeWakeApp.swift(MenuBarExtra)  AppModel.swift(@MainActor 协调者)
    Peer/       Discovery.swift  PeerConnection.swift  Messages.swift
    Security/   Pairing.swift  SecureChannel.swift  KeychainStore.swift
    Wake/       DisplayWaker.swift  DisplayStateMonitor.swift
    Trigger/    EdgeGesture.swift(纯状态机)  PointerMonitor.swift  FullscreenDetector.swift  Hotkey.swift  SideLearner.swift(纯逻辑)
    Checks/     SystemChecks.swift  DeepLinks.swift
    UI/         MenuPanel.swift  OnboardingView.swift  SettingsView.swift  PairingView.swift  WakeHUD.swift
    Resources/  Localizable.xcstrings
  Tests/EdgeWakeTests/  EdgeGestureTests  SideLearnerTests  PairingTests  SecureChannelTests  MessagesTests
```
设计原则：`EdgeGesture` 和 `SideLearner` 是不依赖系统的纯逻辑，输入是事件序列，输出是判定结果，可以完整做单元测试。`AppModel` 只负责组装各模块，避免重蹈 unictrl 那个 967 行 `AppController` 的覆辙。

可参考的 unictrl 设计（只参考思路，不拷贝代码）：边缘判定 `macos/Sources/Unictrl/InputCapture.swift` 的 `edgeDisplay(at:side:)`；显示器几何 `Displays.swift`；`MenuBarExtra` 的写回陷阱 `UnictrlApp.swift`；登录项 `AppController.setLoginItem`；打包流程 `macos/build-app.sh`。


## 实现记录（2026-10-11，与上文规格的差异和补充）

**按 HIG 评审（apple-design-skill）做的调整**
- 菜单栏扩展改为原生菜单（`.menuBarExtraStyle(.menu)`）。依据 `the-menu-bar.md › Menu bar extras`：“Display a menu — not a popover”。每台对端占一个分组，分组里先是一行状态（不可点），再是“唤醒显示器”命令。
- 菜单栏图标是模板图像，系统会把它染成单色，所以“需要处理”用符号形状区分（`display.trianglebadge.exclamationmark`），不用颜色。规格里原先写的“图标颜色表示状态”作废。
- 设置向导去掉了底部操作栏。依据 `windows.md`：“Avoid putting critical information or actions in a bottom bar”。分组标题也去掉了编号，因为“位置”这一组只在配对后出现，编号会跳号。
- 撞击次数改成下拉选择（2/3/4），不再用步进器。依据 `pickers.md`：短列表适合用下拉按钮。

**规格偏差**
- **配对密钥存放位置**：规格写的是存钥匙串，实际改为 `~/Library/Application Support/EdgeWake/peers.json`，文件权限 0600。原因是传统钥匙串条目绑定代码签名，每次重新构建都可能要求输入登录密码，这和“不输密码”的目标冲突。这把密钥只能用来点亮这台 Mac 的屏幕，风险可以接受。
- **双向连接**：macOS 应用防火墙（这台机器开着，而且是隐身模式）会**静默丢弃**发给未放行程序的局域网连接，而回环地址不受影响。这是 M0 实测发现的。因此改为两台 Mac 互相拨号，只要有一个方向能连通就够用；如果两条连接都建立了，双方都保留设备 ID 较小那一方拨出的那条，保证结果一致。另外，检查清单里新增了“防火墙允许 EdgeWake 连接”一项，用 `socketfilterfw --getappblocked` 检测，不需要 root 权限。
- **设置向导窗口**：由 AppKit 的 `SetupWindowController` 持有，不用 SwiftUI 的 `Window` 场景。原因是首次启动、对端发起配对、对端请求“在此显示”这几个时机，屏幕上都没有可以调用 `openWindow` 的视图。
- **全局快捷键**：由 `KeyboardShortcuts` 库完成注册（底层是 Carbon `RegisterEventHotKey`），这个库同时提供录制快捷键的界面。
- **蓝牙状态**：从 `system_profiler SPBluetoothDataType -json` 读取。`com.apple.Bluetooth` 配置里没有 `ControllerPowerState` 这个键，而 IOBluetooth 和 Core Bluetooth 都会弹出权限请求，所以都不用。
- **代码分层**：拆成三个 target。`EdgeWakeCore` 放纯逻辑和加密，`EdgeWakePeer` 放网络层，`EdgeWake` 是 App 本身。网络层独立出来，是为了让测试能通过真实的 Bonjour 和 TCP（走回环）跑完整流程。

**连接安全加固**
- `hello` 之后双方各发一帧加密的 `LinkConfirmation`（带本机名称），能解开对方这一帧才算连接就绪；名称以这一帧为准，`hello` 里的明文名称不采信。只有就绪的连接参与去重。
- 配对证明和长期密钥都绑定双方设备 ID。显示配对码的一方在错误次数用尽后，60 秒内拒绝新的配对请求。
- 握手 10 秒内没完成就断开（正在配对的连接放宽到配对码有效期 2 分钟）；未就绪的传入连接最多 8 条。

**代码评审后的调整（App 层）**
- 唤醒记账抽成 `EdgeWakeCore/WakeScheduler`（纯状态机，有单测）：冷却从收到 `wakeAck` 开始计；没有回音的唤醒 4 秒后作废，可以立即重试；离线提示按冷却节流。
- 发起配对时立即持有连接，握手前失败也会结束配对，不会卡在“正在请求配对码”。
- 并发的检查刷新只采用最新一次的结果；子进程 10 秒超时；`pmset` 只看设置值，不看临时断言。
- 离线对端的检查结果不再显示（显示“等待中”）。
- 取消配对时通知对端（`unpaired` 消息），对端同步忘记这台 Mac。
- 全屏检测容忍刘海屏顶部的安全区；“指针到达”要求前后两次采样都贴在同一边缘。

**已知限制**
- 6 位配对码：在 2 分钟配对窗口内，主动拦截流量的攻击者可以离线暴力破解配对码。可接受的理由是：通道里只传“唤醒”和状态信息。
- 被唤醒端必须处于醒着的状态（显示器可以是关的）。系统睡眠后无法唤醒，也不做网络唤醒（WoL）。

**M0 预研状态**
1. 不需要权限的全局鼠标监听：双机实测通过（2026-10-11），撞边可以触发，不需要辅助功能权限。
2. `IOPMAssertionDeclareUserActivity` 在锁屏且屏幕关闭时点亮：双机实测通过，通用控制随后恢复。
3. 不弹窗读取蓝牙状态：已通过 `system_profiler` 验证。
4. 不需要屏幕录制权限判断全屏：已实现（`CGWindowListCopyWindowInfo` 读取窗口边界），待实测。
