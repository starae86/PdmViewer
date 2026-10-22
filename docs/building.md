# 桌面多架构构建

## 支持范围

| 平台 | 架构参数 | 构建环境 |
| --- | --- | --- |
| Windows Intel/AMD 64 位 | `x64` | Windows + x64 Flutter/Dart SDK + Visual Studio C++ 桌面开发工具 |
| Windows ARM64 | `arm64` | Windows on ARM + 原生 ARM64 Flutter/Dart SDK + ARM64 C++ 构建工具 |
| macOS Intel | `x64` | macOS + Xcode，以及插件所需的 CocoaPods / SwiftPM 环境 |
| macOS Apple Silicon | `arm64` | macOS + Xcode，以及插件所需的 CocoaPods / SwiftPM 环境 |
| macOS 通用包 | `universal` | 同时支持 `x86_64`、`arm64` 的 Xcode、Flutter 引擎和原生插件 |

这里的 `x64` 指 x86-64 / AMD64，不是 32 位 x86。`arm64` 也不是 32 位 ARM。
当前 Flutter 桌面目标不支持本项目的 32 位 x86 / ARM 构建，脚本会拒绝这些参数。

Windows Flutter 构建根据其 Dart 进程 ABI 选择目标架构，没有可供此脚本使用的目标架构切换参数。
因此 ARM Windows 上使用模拟运行的 x64 SDK 仍然只能生成 x64 程序。
脚本使用运行它的 Dart 所属 Flutter SDK，遇到架构不匹配会报错，不会把 x64 产物标成 ARM64。

macOS 通过 Flutter 转发到 Xcode 的 `ARCHS` 设置选择架构，并关闭 `ONLY_ACTIVE_ARCH`。
通用包同时包含 Intel 和 Apple Silicon；原生插件也必须支持相应架构。
Windows 与 macOS 必须分别在对应系统上构建，不能在 Windows 上构建 macOS 应用。

## 使用

在项目根目录运行，确保 PATH 中的 `dart` 来自 Flutter SDK：

```sh
dart run tooling/build_desktop.dart --help
dart run tooling/build_desktop.dart
```

不传参数时，Windows 构建当前 SDK 的原生架构，macOS 构建通用包，均使用 Release 模式。

```sh
dart run tooling/build_desktop.dart --platform=windows --arch=x64
dart run tooling/build_desktop.dart --platform=windows --arch=arm64
dart run tooling/build_desktop.dart --platform=macos --arch=universal
dart run tooling/build_desktop.dart --platform=macos --arch=x64
dart run tooling/build_desktop.dart --platform=macos --arch=arm64
```

预览构建计划，不执行 Flutter，也不验证构建机和工具链：

```sh
dart run tooling/build_desktop.dart --platform=windows --arch=arm64 --dry-run
```

## 产物

- Windows x64：`build/windows/x64/runner/Release/`。
- Windows ARM64：`build/windows/arm64/runner/Release/`。
- macOS：`build/macos/Build/Products/Release/PdmViewer.app`。

Windows 需要分发完整 Release 文件夹，不能只复制 `PdmViewer.exe`。
macOS 不同架构使用同一个默认输出目录，连续构建会覆盖上次产物；需要分别发布时先归档。
脚本校验 Windows EXE 的 PE 架构或 macOS 主程序的 Mach-O 架构。
完整插件和系统版本兼容性仍需在目标设备测试，主程序架构正确不等于全平台验证通过。
脚本不修改项目文件、不清理现有构建目录、不改变输出位置，也不生成安装器或处理发布签名 / 公证。
Java 运行时和 JDBC 驱动包不随此脚本打包。

## Linux 是否需要按发行版构建

**不必每个发行版都编译一次，但需要按 CPU 架构和运行库兼容范围构建并测试。**

主要差异包括 glibc、libstdc++、GTK、SQLite 和原生插件依赖。
在较新系统编译的程序可能无法在较旧系统运行；通常应在计划支持的较旧基线环境构建，
再对较新发行版验证。不能仅凭“都是 Linux”就认为二进制一定兼容。
Alpine 使用 musl，与常见 glibc 桌面发行版不属于同一个兼容目标。

| 主流系列 | 常见发行版 | 常用分发形式 |
| --- | --- | --- |
| Debian / Ubuntu | Debian、Ubuntu LTS、Linux Mint、Pop!_OS | `.deb`、Flatpak、AppImage |
| Fedora / RHEL | Fedora、RHEL、Rocky Linux、AlmaLinux | `.rpm`、Flatpak、AppImage |
| SUSE | openSUSE Leap / Tumbleweed、SLES | `.rpm`、Flatpak、AppImage |
| Arch | Arch Linux、Manjaro、EndeavourOS | PKGBUILD / AUR、Flatpak、AppImage |

选择打包格式和选择编译环境是两回事：兼容的同一份二进制可以装入不同格式，
但 `.deb` / `.rpm` 的依赖声明和桌面集成需要各自维护，RPM 也不能假定跨所有系列通用。
AppImage 不能消除所有 glibc 和系统依赖限制；Flatpak 可通过固定运行时减少发行版差异，仍需维护权限及运行时。

建议首版先选择一个仍受 Flutter 支持的 Ubuntu LTS 作为基线，提供 x64 包，
在另一套 Ubuntu / Debian 和 Fedora 上做运行测试。ARM64 另建构建任务；
只有确实需要支持较旧企业发行版或特殊依赖时，再单独维护构建基线。

**当前项目没有 Linux 平台目录，统一脚本暂不接受 `--platform=linux`。**
正式支持前需要创建 Linux runner，验证现有插件的 Linux 支持、窗口行为、字体、文件夹打开、
SQLite 动态库和 JDBC 执行路径，再配置 Linux 构建与发布；不是新增一条构建命令就完成适配。

## 验证边界

新增脚本已提供构建计划和参数校验测试，可通过 `--dry-run` 检查命令。
各架构 Release 二进制必须在相应构建环境实际编译和运行验收；干跑不代表交付包已经生成。
