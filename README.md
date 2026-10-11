# EdgeWake

**English** · [简体中文](#简体中文)

Universal Control drops a Mac whose display has turned off, even though the Mac itself is awake —
lock the screen and press Esc, and the pointer can no longer cross over. EdgeWake fixes that: bump
the screen edge facing the other Mac twice, and its display wakes up so Universal Control
reconnects.

- **Edge gesture**: two bumps within 0.6 s on the edge facing the other Mac. It only fires when that
  Mac reports its display is off, no mouse button is held, and no app is full screen.
- **Shortcut**: ⌃⌥⌘W wakes every paired Mac (changeable in Settings).
- **Setup checklist** for both Macs side by side: Wi‑Fi, Bluetooth, Handoff, firewall, sleep,
  Apple Account and Universal Control, with buttons that open the right System Settings page — on
  the other Mac too.
- **Learns the arrangement**: when the pointer crosses, EdgeWake notices which side the other Mac
  is on and updates itself.
- **No password, no special permission**: no SSH, no sudo, no Accessibility access. Macs pair once
  with a 6-digit code; everything after that is encrypted (P‑256 ECDH, AES‑256‑GCM).

Requires macOS 15 or later on every Mac, on the same local network. Install EdgeWake on each one.

## Build

```sh
swift test                 # unit and loopback integration tests
./scripts/build-app.sh     # .build/EdgeWake.app
./scripts/make-dmg.sh      # .build/EdgeWake-<version>.dmg
```

Signing uses `$EDGEWAKE_SIGNING_IDENTITY`, else the first "Apple Development" certificate, else
ad-hoc. Use a stable certificate (Xcode › Settings › Accounts creates a free one) so macOS
remembers the Local Network and firewall approvals across rebuilds. No prebuilt binaries are
published.

`EDGEWAKE_SNAPSHOTS=/tmp/shots swift run EdgeWake` renders the Setup and Settings windows to PNG
files in debug builds.

## Layout

| Target | What |
| --- | --- |
| `EdgeWakeCore` | Edge gesture and side-learning state machines, screen-edge geometry, pairing crypto, encrypted channel, wire messages |
| `EdgeWakePeer` | Bonjour discovery, pairing handshake and encrypted links (Network.framework) |
| `EdgeWake` | The menu bar app: pointer monitoring, display wake, system checks, UI |

See [docs/SPEC.md](docs/SPEC.md) for the product specification and design decisions.

## License

MIT.

---

## 简体中文

通用控制会断开显示器已关闭的 Mac，即使那台 Mac 本身没有睡眠。比如锁屏后按 Esc 关屏，指针就移不过去了。
EdgeWake 解决这个问题：朝另一台 Mac 所在的屏幕边缘连续撞两下，它的显示器就会亮起，通用控制随即重新连接。

- **撞边手势**：0.6 秒内在朝向对端的边缘撞两次。只有对端上报显示器已关闭、没有按住鼠标键、且没有全屏 App 时才会触发。
- **快捷键**：⌃⌥⌘W 唤醒所有已配对的 Mac，可在设置里修改。
- **双机设置清单**：Wi‑Fi、蓝牙、接力、防火墙、睡眠、Apple 账户、通用控制，并排显示两台 Mac 的状态；按钮可以直接打开对应的系统设置页面，包括在另一台 Mac 上打开。
- **自动学习方位**：指针穿越时，EdgeWake 会识别另一台 Mac 在哪一侧并自动更新。
- **不需要密码和特殊权限**：不用 SSH、不用 sudo、不需要辅助功能权限。两台 Mac 用 6 位码配对一次，之后的通信全部加密（P‑256 ECDH、AES‑256‑GCM）。

每台 Mac 都需要 macOS 15 或更高版本，并处于同一局域网，两台都要安装 EdgeWake。构建方法见上文。
