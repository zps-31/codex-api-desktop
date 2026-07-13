# Codex API Plus / Codex Meter Plus 安全审查

审查日期：2026-07-13
范围：两个 Swift 应用的运行时源码、配置与发布脚本。

## 结论

审查中确认的安全问题均已修复；复查未发现仍可报告的高危或中危漏洞。本机 API 路由只监听 `127.0.0.1`，钥匙串中的 API Key 不写入 Codex 子进程环境或普通配置文件。

## 已修复

- 凭据重定向：API 代理、健康检查和 Meter 计费请求只允许同源重定向，避免 `Authorization`、自定义认证头和 `New-Api-User` 被转发到其他源。
- 明文凭据：带 API Key 的远程 Base URL 强制使用 HTTPS；HTTP 仅允许 loopback。
- 混淆代理：本机路由只接受 `POST /v1/responses`，不再把任意路径代理到带凭据的上游。
- 请求解析崩溃：拒绝负数、溢出或超过 16 MiB 的 `Content-Length`/chunked 请求体。
- 内存耗尽：代理写队列上限 8 MiB，普通 HTTP 响应上限 4 MiB，错误响应上限约 1 MiB。
- 本地文件耗尽：会话枚举、JSONL、配置和任务桥接文件均设置数量/大小上限。
- 旧权限迁移：已有运行目录、配置、模型目录、PID 和日志文件会在启动时
  重新收紧为仅当前用户可访问。
- 元数据耗尽：Meter 会话索引和模型目录读取上限为 8 MiB，不再常驻保存
  整份文件副本。
- 计数溢出：Meter token 汇总改为饱和加法，恶意极值不会触发 Swift 整数陷阱。
- 自定义认证头：只接受 RFC token 字符并拒绝 `Host`、`Content-Length`、`Connection`、`Transfer-Encoding`。

## 验证

- `swift run CodexAPIManagerPlus --self-test`：PASS。
- `meter/scripts/verify.sh`：PASS，包括已安装的官方 Codex 和 API Plus 会话数据。
- 两个项目 Debug/Release 编译：PASS。
- 两个 `.app` 的 `codesign --verify --deep --strict`：PASS。
- 实际 Codex CLI 经 `127.0.0.1:62139/v1/responses` 完成流式请求并返回 `SECURITY_OK`。
- 2026-07-13 的官方 Codex 事件仅返回 10080 分钟周窗口，旧 300 分钟
  窗口已不再返回；Meter 的运行态选择与新额度规则一致。
- 官方 `gpt-5.5` 与 API 私有 `gpt-5.6-sol` 并行真实请求均成功，官方
  配置哈希在两次请求前后保持不变。
- 候选版本：Codex API 桌面版 Plus 2.14.2；Codex Meter Plus 2.5.2。

## 性能与兼容性复查

- 两款候选应用均为 `arm64 + x86_64` 通用二进制。
- API Codex 使用独立 `HOME`、Core Foundation home、XDG、`CODEX_HOME`
  和 Electron 数据目录；与官方 ChatGPT Codex 并行运行时不会改写
  `~/.codex/config.toml`。
- Meter 对官方约 10.58 亿和 API Plus 约 10.87 亿 Token 的真实历史验证
  通过；35 秒累计 CPU 增加约 0.03 秒，RSS 回落到约 55.8 MiB。
- API 管理器在真实路由运行的 35 秒窗口内累计 CPU 增加约 0.12 秒，
  RSS 回落到约 27.7 MiB。
- Meter 改为固定缓冲区流式解析后，能够计入此前被 64 MiB 上限整份忽略的
  89 MiB 有效会话文件。
- 两款应用会自动迁移旧用户路径；不兼容当前 Mac 架构的 Codex 候选会被
  跳过并回退到可执行的官方安装。

## 正式分发门槛

本机当前没有有效 Developer ID 签名身份，因此只能生成临时签名测试包。
发布脚本已加入正式模式，并在缺少签名身份或 `notarytool` 凭据时失败；只有
Developer ID、Hardened Runtime、时间戳、公证、staple 和 Gatekeeper 全部
通过后，才能将产物标记为正式销售发行版。

## 剩余非安全提示

API 版 Codex 未登录 ChatGPT 账户时，官方插件目录会出现 HTTP 401/451 警告；这不影响模型 API 请求或用量统计，也不代表 API Plus 路由失败。
