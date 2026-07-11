# Codex API 桌面版

一个用于管理 OpenAI-compatible API 配置并启动独立 Codex 桌面进程的
macOS 应用。它与官方 Codex 的配置和应用数据相互隔离。

> [!IMPORTANT]
> 本项目是非官方社区工具，与 OpenAI 无隶属或背书关系。Codex 和 OpenAI
> 是其各自权利人的商标。

## 功能

- 在应用内切换 API Base URL、模型、认证方式与 API Key。
- API Key 保存到 macOS 钥匙串，不写入项目源码或普通配置文件。
- 使用独立的 `CODEX_HOME` 和桌面 Chromium 数据目录。
- 支持 OpenAI、自定义 OpenAI-compatible Responses API、Mistral、Ollama
  与 LM Studio 模板。
- 可以与官方 Codex 同时运行，不修改 `~/.codex`。

第三方 API 必须兼容 OpenAI Responses 协议、流式输出和工具调用。仅提供
Chat Completions 的 API 需要先接入兼容代理。

## 系统要求

- macOS 14 或更高版本
- 已安装官方 Codex macOS 应用，或可用的 Codex CLI
- 从源码构建时需要 Xcode Command Line Tools 或 Xcode

## 下载与安装

1. 打开本仓库右侧的 **Releases**。
2. 下载最新版 `Codex-API-Desktop-版本号.zip`。
3. 解压后将应用拖入“应用程序”文件夹。
4. 首次打开时，如果 macOS 阻止运行，请在“系统设置 > 隐私与安全性”中
   选择“仍要打开”。

Release 中的应用采用临时签名，未经过 Apple 公证。请只从本仓库下载，并
在使用前核对 Release 页面提供的 SHA-256。

## 使用方法

1. 打开“Codex API 桌面版”。
2. 在左侧选择服务商模板，或新增自定义配置。
3. 填写 API Base URL、模型和认证方式。
4. 输入 API Key 并保存。Key 会存入 macOS 钥匙串。
5. 选择工作目录，然后点击“启动 Codex 桌面 API 版”。

应用数据保存在：

```text
~/Library/Application Support/Codex API Manager/
```

其中 API 版 Codex 使用 `codex-home`，桌面数据使用 `desktop-data`。卸载应用
不会自动删除这些数据。

## 从源码构建

```zsh
git clone <本仓库地址>
cd CodexAPIManager
swift build
swift run CodexAPIManager --self-test
./script/build_and_run.sh
```

生成可发布的应用和 zip：

```zsh
./script/build_and_run.sh package
```

产物位于 `dist/`。

## 隐私

应用不会把凭据上传到本项目维护者的服务器。启动 Codex 后，请求会发送给
你所选择的 API 服务商；其数据处理方式受对应服务商的隐私政策约束。

## 已知说明

- CCTQ 模板使用 `https://www.cctq.ai/v1` 和 Responses API。
- 模板包含 `gpt-5.6-sol`、`gpt-5.6-terra`、`gpt-5.6-luna` 等模型配置。
- 某个第三方模型返回 503 通常表示该模型后端暂不可用，不代表本地配置损坏。
