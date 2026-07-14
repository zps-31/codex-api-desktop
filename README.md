# Codex API Desktop Plus

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)](https://www.apple.com/macos/)
[![Universal](https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-0A84FF)](README.md)
[![Release 2.14.4](https://img.shields.io/badge/release-2.14.4-30D158)](CHANGELOG.md)

一个原生 macOS 配置管理器，用于管理 OpenAI-compatible Responses API
配置，并启动与官方 Codex 数据隔离的 API 版 Codex 桌面进程。

> [!IMPORTANT]
> 本项目是非官方第三方工具，与 OpenAI 无隶属或背书关系。Codex 和 OpenAI
> 是其各自权利人的商标。

## 当前版本

**2.14.4**, 2026-07-13

- 发布包：`Codex-API-Desktop-Plus-2.14.4.zip`
- 校验文件：`Codex-API-Desktop-Plus-2.14.4.zip.sha256`
- [直接下载 2.14.4](https://github.com/zps-31/codex-api-desktop/raw/refs/heads/main/downloads/Codex-API-Desktop-Plus-2.14.4.zip)
- SHA-256：`a695e332224897dd7400c45c0c1b40f7a6fdcf577c4956fbfc0deec89aa66fe2`
- 完整变更：[CHANGELOG.md](CHANGELOG.md)

## 主要功能

- 管理 API Base URL、模型 ID、认证方式、项目目录和启动场景。
- 新增、复制、删除和切换模型配置。
- 支持需要 API Key 的远程服务，以及无需 Key 的 Ollama、LM Studio 等本地服务。
- API Key 只保存到 macOS 钥匙串。
- 自动修复缺失的用户默认/搜索钥匙串设置，并兼容旧版密钥服务名。
- 启动前检查凭据、工作目录、模型目录和目标模型。
- 使用独立 `HOME`、`CFFIXED_USER_HOME`、XDG、`CODEX_HOME` 与桌面数据
  目录，不修改官方 `~/.codex`，可与 ChatGPT 账户同时运行。
- 自动迁移其他 Mac 用户目录下的旧项目路径，并跳过当前机器无法执行的
  Codex 应用架构。
- 本机 Responses API 路由自动选择真实上游、模型和钥匙串凭据。
- 状态栏显示当前会话、最近请求和模型上下文窗口。
- 保存最近 100 次启动记录，并与 Codex Meter Plus 同步任务预算。

第三方 API 必须兼容 OpenAI Responses API、流式输出和工具调用。只支持
Chat Completions 的服务需要先接入兼容代理。

## 系统要求

- macOS 14 或更高版本
- Apple Silicon 或 Intel Mac
- 已安装独立的 `Codex API Plus.app` 运行时。官方 Codex 保持为独立账户
  应用，API 管理器不会将 API 环境注入官方应用。

## 安装

1. 下载 zip 和同名 `.sha256` 文件并核对 SHA-256。
2. 解压后将 `Codex API 桌面版 Plus.app` 移到 `/Applications`。
3. 新建或选择配置，保存凭据，运行启动前检查后启动 API Codex。

正式发行包应使用 Developer ID 签名并通过 Apple 公证。临时签名的测试包
只适合本机验收，Gatekeeper 会拒绝其作为普通互联网下载直接分发。

## 本机数据

应用数据默认保存在：

```text
~/Library/Application Support/Codex API Manager Plus/
```

API Key 位于 macOS 钥匙串，不写入仓库、普通配置文件或 Codex 子进程环境。
卸载应用不会自动删除配置与会话数据。

## 从源码构建

```zsh
git clone https://github.com/zps-31/codex-api-desktop.git
cd codex-api-desktop
swift build -Xswiftc -warnings-as-errors
swift run CodexAPIManagerPlus --self-test
swift run CodexAPIManagerPlus --verify-keychain
./script/build_and_run.sh
```

默认发布构建同时包含 `arm64` 和 `x86_64`：

```zsh
./script/build_and_run.sh package
```

正式签名和公证：

```zsh
DISTRIBUTION=1 \
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="your-notarytool-profile" \
./script/build_and_run.sh package
```

脚本会强制执行 Hardened Runtime、可信时间戳、公证、staple、Gatekeeper
评估和 zip 完整性检查；任一环节失败都不会把产物当成正式发行版。

图标可通过 `./script/generate_icons.sh` 重新生成。发布产物位于 `dist/`。
源码构建需要 Xcode Command Line Tools 或 Xcode。

## 安全与隐私

本机代理只监听 `127.0.0.1`，带凭据的远程服务必须使用 HTTPS，跨域重定向
不会携带认证信息。详细边界与报告方式见 [SECURITY.md](SECURITY.md)，数据
处理说明见 [PRIVACY.md](PRIVACY.md)。
