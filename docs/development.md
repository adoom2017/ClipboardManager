# 开发指南

## 前置条件

### macOS

- macOS 14+
- Xcode 15+
- Swift 5.9
- XcodeGen

### Windows

- Windows 10/11
- Flutter SDK，满足 `pubspec.yaml` 中的 Dart SDK 约束
- Visual Studio 的 Desktop development with C++ 工作负载

## 常用命令

所有命令从对应子项目目录执行。

### macOS

```bash
cd ClipboardManager
xcodegen generate
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' build
xcodebuild test -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS'
```

修改 `project.yml` 或新增 Swift 文件后运行 `xcodegen generate`。不要手工维护 `.xcodeproj` 文件引用。命令行无需签名验证时可追加 `CODE_SIGNING_ALLOWED=NO`。

### Windows

```bash
cd ClipboardManager-Flutter
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build windows --release
```

Release 输出位于 `build/windows/x64/runner/Release/`。Windows 构建、托盘、DPAPI、注册表和全局快捷键必须在 Windows 主机验证。

## 工作树与生成物

- 工作区根目录不是两个应用的共同 Git 仓库；提交前分别在 `ClipboardManager/` 和 `ClipboardManager-Flutter/` 检查状态。
- 跨端共享文档位于 macOS 仓库的 `docs/`，随 macOS 仓库提交；Windows 仓库的 README 通过 GitHub 链接引用。
- `ClipboardManager.xcodeproj` 由 `project.yml` 生成。Swift 文件增删或工程设置变化后执行 `xcodegen generate`，并提交生成结果。
- `build/`、`.dart_tool/`、DerivedData、`*.profraw`、日志和发布产物都是生成物，不得提交。
- 修改 `pubspec.yaml` 后执行 `flutter pub get` 并提交更新后的 `pubspec.lock`。只保留代码实际使用的运行时依赖和代码生成工具。

## 清理与静态检查

删除公开方法、兼容别名或依赖前，先全仓搜索调用点，再用对应平台的构建和测试确认。测试不应通过只供测试使用的生产代码别名间接覆盖功能，应直接调用正式 API。

```bash
cd ClipboardManager-Flutter
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Swift 编译器不会报告所有未使用的内部声明，因此清理 Swift 代码时还需检查类型、方法、扩展和通知名的引用；删除 Swift 文件后必须重新生成 Xcode 工程。

## 正式版打包

两个脚本都会构建 Release、整理便携目录、生成版本化 ZIP 和 SHA-256 文件。macOS 脚本默认不运行测试；Windows 脚本默认先执行测试和静态分析。产物均在子项目的 `build/` 下，不进入 Git。

### macOS 打包

本机测试包（ad-hoc 签名）：

```bash
cd ClipboardManager
./scripts/build-release.sh
```

默认产物：

```text
build/Release/ClipboardManager.app
build/Release/ClipboardManager-macOS-<version>.zip
build/Release/ClipboardManager-macOS-<version>.zip.sha256
```

对外发布需要 Developer ID Application 证书与 Apple 公证。先把 notarytool 凭据存入 Keychain：

```bash
xcrun notarytool store-credentials ClipboardManagerNotary \
  --apple-id 'APPLE_ID' \
  --team-id 'TEAM_ID' \
  --password 'APP_SPECIFIC_PASSWORD'
```

然后执行：

```bash
SIGNING_IDENTITY='Developer ID Application: Company Name (TEAM_ID)' \
DEVELOPMENT_TEAM='TEAM_ID' \
NOTARY_PROFILE='ClipboardManagerNotary' \
./scripts/build-release.sh
```

脚本启用 Hardened Runtime，验证 codesign，等待公证完成、staple ticket，再重新生成 ZIP 和校验和。仅传 `SIGNING_IDENTITY` 而未传 `NOTARY_PROFILE` 时，产物已签名但未公证。

可选参数通过环境变量传入：

| 变量 | 默认值 | 用途 |
|---|---|---|
| `OUTPUT_DIR` | `build/Release` | 产物目录 |
| `DERIVED_DATA_PATH` | `/tmp/ClipboardManager-Release` | Xcode DerivedData |
| `RUN_TESTS` | `0` | 设为 `1` 时在构建前运行测试 |
| `SIGNING_IDENTITY` | `-` | ad-hoc 或 Developer ID 身份 |
| `DEVELOPMENT_TEAM` | 空 | Apple Team ID |
| `NOTARY_PROFILE` | 空 | notarytool Keychain profile |

### Windows 打包

必须在安装了 Flutter 与 Visual Studio C++ 桌面工作负载的 Windows 主机执行：

```powershell
cd ClipboardManager-Flutter
powershell -ExecutionPolicy Bypass -File .\scripts\build-release.ps1
```

默认产物：

```text
build\release\ClipboardManager-Windows-<version>\
build\release\ClipboardManager-Windows-<version>.zip
build\release\ClipboardManager-Windows-<version>.zip.sha256
```

使用 Windows 代码签名证书：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-release.ps1 `
  -BuildName '1.0.0' `
  -BuildNumber '1' `
  -CertificateThumbprint 'CERTIFICATE_SHA1_THUMBPRINT'
```

传入证书指纹时，脚本使用 `signtool.exe` 对包内 EXE/DLL 签名、添加 SHA-256 时间戳并逐个验证。未传指纹时会生成未签名 ZIP 并输出警告。

可选参数：

| 参数 | 默认值 | 用途 |
|---|---|---|
| `-OutputDirectory` | `build\release` | 产物目录 |
| `-BuildName` | `pubspec.yaml` 版本 | Windows 产品版本 |
| `-BuildNumber` | `pubspec.yaml` build number | 构建号 |
| `-CertificateThumbprint` | 空 | 当前证书存储中的 SHA-1 指纹 |
| `-TimestampUrl` | DigiCert 时间戳服务 | RFC 3161 时间戳地址 |
| `-SkipTests` | false | 跳过 `flutter test`；静态分析仍执行 |

### 校验产物

```bash
cd ClipboardManager/build/Release
shasum -a 256 -c ClipboardManager-macOS-<version>.zip.sha256
```

```powershell
Get-FileHash .\ClipboardManager-Windows-<version>.zip -Algorithm SHA256
Get-Content .\ClipboardManager-Windows-<version>.zip.sha256
```

## 代码约定

- Swift 使用 4 空格，类型 `PascalCase`，成员 `camelCase`；视图、状态、服务分别放在既有目录。
- Dart 遵循 `analysis_options.yaml` 和 `dart format`，文件使用 `snake_case.dart`。
- macOS 新设置：普通值进入 `UserDefaults`；凭据进入 `SecureCredentialStore`，不得把密钥写回明文设置。
- Windows 新凭据通过 `SecureCredentialStore`/DPAPI 保存。
- 同步派生密钥仅保留在内存中，不得添加序列化或持久化接口。
- 修改 `ClipboardItem` 时必须兼容旧 JSON；Swift 解码新增字段需提供默认值。
- 同步协议字段或密码学变化必须同时修改两个应用和 macOS 仓库的 `docs/sync-protocol.md`。
- 不要加入明文同步回退。

## 测试要求

- 持久化、隐私、监听和同步加密变更需要 macOS XCTest。
- Flutter 协议和业务逻辑使用 `flutter_test`；不要恢复默认计数器模板测试。
- 加密实现必须保留 Swift/Dart 共用的固定测试向量，防止两端各自通过但无法互解。
- UI 变更至少执行 macOS 构建、`flutter analyze` 和现有两端测试。

## 发布前检查

1. 两个工作树分别检查 `git status`，不要把一个仓库的提交混入另一个。
2. macOS 运行 `xcodegen generate` 后构建和测试。
3. Windows 运行 `flutter analyze`、`flutter test` 和 Release 构建。
4. 在真实 Windows 环境验证 DPAPI、托盘、`Alt+V`、自动粘贴和开机启动。
5. 使用两台设备验证发现、PIN 不一致错误、加密同步和 ACK 超时。

## 常见问题

- macOS 自动粘贴失败：检查辅助功能权限，重新启动应用后重试。
- Flutter 窗口无法出现：使用托盘菜单或确认 `Alt+V` 未被其他程序占用。
- 历史为空：检查历史开关、隐私过滤规则和持久化目录权限。
- 测试不能启动 macOS runner：确认测试 scheme 为 `ClipboardManager`，并允许 `xcodebuild` 访问测试服务。
- 设备无法发现或同步：按[同步协议](sync-protocol.md)的排障章节检查。
