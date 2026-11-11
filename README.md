# SMART Info Native

macOS 原生（SwiftUI）磁盘 SMART 信息查看器。通过 `diskutil` 列举物理磁盘，调用 [smartmontools](https://www.smartmontools.org/) 7.5 的 `smartctl -x --json=ov`，把 NVMe / ATA 的完整 SMART 数据以中文表格呈现。

**只读工具**：不运行自检、不修改磁盘、不安装内核扩展。缺失数据一律显示为「不可用」，不会补零或臆测。

当前版本：**1.1.3 (build 5)** · macOS 13+ · Apple Silicon (arm64) · GPL v2

---

## 功能

- 侧边栏列出全部物理磁盘，显示容量、接口、位置与健康状态，可整行点选
- NVMe 健康信息日志、ATA 属性表的完整展开，含中文说明、单位、阈值、逐位关键告警、全部八个可选温度传感器
- 保留 `smartctl` 原始数值字符串与完整文本输出；上游 7.5 JSON 未给出的热管理计数从原始文本中还原
- 所有分组默认展开，可完整复制表格内容，支持横向滚动查看长字段
- 序列号等标识符默认遮蔽，导出 JSON 时才会包含
- 明细在后台线程预先计算并复用原生表格行，切换大容量磁盘不会卡顿
- 附带解析器单元测试（`Tests/SMARTTests.swift`），构建时自动运行

## 下载与安装

前往 [Releases](https://github.com/yuchu2016/smart-info-native/releases) 下载 `SMART-Info-Native-1.1.3-Mac.zip`，解压后把 `SMART Info Native.app` 拖进「应用程序」即可。

> **首次打开提示**：本构建使用 ad-hoc 签名，**未做 Apple Developer ID 签名与公证**。macOS 可能提示「无法验证开发者」。右键点击应用 → 「打开」→ 确认，或在「系统设置 → 隐私与安全性」中允许。也可以执行：
>
> ```sh
> xattr -d com.apple.quarantine "/Applications/SMART Info Native.app"
> ```

读取部分磁盘的 SMART 数据可能需要管理员权限；若某块盘显示「未取得 SMART 数据」，可尝试用 `sudo` 启动，或确认该设备/USB 桥接芯片是否被 smartmontools 支持。

## 系统要求

| 项目 | 要求 |
|---|---|
| 系统 | macOS 13.0 (Ventura) 及以上 |
| 架构 | Apple Silicon / arm64（当前构建未包含 x86_64） |
| 构建 | Xcode 或 Command Line Tools（需要 `xcrun swiftc`、`iconutil`、`codesign`） |
| 引擎 | 内置 `smartctl`，或系统已安装 smartmontools（如 `brew install smartmontools`） |

## 从源码构建

```sh
git clone https://github.com/yuchu2016/smart-info-native.git
cd smart-info-native

./build-engine.sh   # 可选：下载并编译 smartmontools 7.5 的 smartctl 到 Engine/
./build.sh          # 编译应用、生成图标、运行单元测试

open "Build/SMART Info Native.app"
```

说明：

- `build-engine.sh` 从 SourceForge 下载官方 `smartmontools-7.5.tar.gz`（GPL v2），在 `EngineWork/` 中编译 arm64 版 `smartctl` 并 ad-hoc 签名。产物 `Engine/smartctl`、`Engine/COPYING` 不入库。
- 跳过引擎构建也可以：应用会依次查找 `Contents/Resources/smartctl` → 环境变量 `SMARTINFO_ENGINE` → `/opt/homebrew/sbin/smartctl` 等 Homebrew 路径。
- `build.sh` 用 `xcrun swiftc -O` 编译 `Sources/` 下三个 Swift 文件，生成 `AppIcon.icns`，打包 `Info.plist`，执行 `codesign --verify --deep --strict`，并编译运行 `Tests/SMARTTests.swift`。
- 可用 `SMARTINFO_BUILD_DIR=/some/path ./build.sh` 指定输出目录；默认输出到 `Build/`。

## 工作原理

```
diskutil list -plist physical        →  物理磁盘 ID 列表
diskutil info  -plist /dev/diskN     →  容量、接口、内置/外置、设备节点
smartctl -x --json=ov <node>         →  NVMe / ATA SMART 原始 JSON + 原始文本
SMARTParser / SMARTPresentation      →  中文表格、单位、阈值、健康判定、遮蔽标识符
```

字段释义参照 smartmontools 7.5 的 `nvmeprint.cpp`、`smartctl.8.in` 以及 NVMe 规范；ATA 描述按属性名称而非仅按数字 ID 匹配，厂商自定义字段保留原值并明确标注为「厂商特定」，不做臆测解释。健康状态是基于阈值的启发式判断，**不能作为磁盘不会故障的保证，请另行保持独立备份**。

## 许可证与致谢

- 本项目 Swift 应用 UI 与 SMART 数据归一化代码为独立实现，按 **GNU GPL v2** 发布，见 [LICENSE](LICENSE) / [COPYING](COPYING)。版本说明与合规声明见 [NOTICE.txt](NOTICE.txt)。
- 内置 `smartctl` 来自官方 **smartmontools 7.5**（2025-04-30, r5714），版权 © 2002–2025 Bruce Allen、Christian Franke 及贡献者，同为 GPL v2。上游源码：<https://downloads.sourceforge.net/project/smartmontools/smartmontools/7.5/smartmontools-7.5.tar.gz>。Release 中的 `*-Source.zip` 附有未修改的上游源码归档，以满足 GPL 对应源码要求。
- 本项目**未**使用原 SMART Info Flutter 版本的代码或二进制资源。

## 已知限制

- 仅构建 arm64；Intel Mac 需自行调整 `build.sh` 中的 `-target` 与 `build-engine.sh` 中的编译参数。
- 未签名/未公证，分发范围限于本地自行构建与本项目 Release。
- USB/SATA 桥接兼容性取决于 macOS、固件、驱动与 smartmontools 后端；解析器有测试覆盖，但本次构建未做真实 USB/SATA 设备实机验证。
- 健康判定为启发式，缺失数据一律显示为不可用。
