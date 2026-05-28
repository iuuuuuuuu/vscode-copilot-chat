# NoLogin Patch 维护指南

> 本文件记录了 `copilot-chat-nologin` 对上游 vscode-copilot-chat 的所有修改。
> 上游更新后，对照本文档重新应用补丁。

## 快速操作

```powershell
# 自动应用补丁 + 构建
.\scripts\apply-nologin-patches.ps1

# 仅应用补丁（不构建）
.\scripts\apply-nologin-patches.ps1 -SkipBuild
```

---

## 变更清单

### A类：防御性 Bug 修复（极少冲突）

| # | 文件 | 改动 | 原因 |
|---|------|------|------|
| A1 | `src/extension/chatSessions/copilotcli/node/ripgrepShim.ts` | `readdir` 前加 `fs.access()` 检查 | VS Code 精简版无 `@vscode/ripgrep/bin`，不检查会 ENOENT 崩溃 |
| A2 | `src/extension/chatSessions/copilotcli/node/nodePtyShim.ts` | 同上模式 | 同上，`node-pty` 目录也可能不存在 |
| A3 | `src/extension/tools/common/virtualTools/virtualToolGrouper.ts` | `computeEmbeddings` 外包 `try/catch` | 无登录时 embeddings 服务不可用，不捕获会阻塞整个聊天 |
| A4 | `src/extension/chatSessions/vscode-node/chatCustomAgentsService.ts` | `vscode.chat.customAgents` 加 `?? []` | 无登录时 `customAgents` 可能为 undefined |
| A5 | `src/extension/chatSessions/vscode-node/chatPromptFileService.ts` | 同上，两处 `?? []` | 同上 |

### B类：No-Login 模式核心支持（低冲突风险）

| # | 文件 | 改动 | 原因 |
|---|------|------|------|
| B1 | `src/extension/byok/common/byokProvider.ts` | `isBYOKEnabled()` 中加 `if (isNoAuthUser) return true` | 让匿名用户也能使用 BYOK 模型 |
| B2 | `src/platform/authentication/vscode-node/copilotTokenManager.ts` | 删除 `GitHubLoginFailed` 错误返回（-6行） | 无 GitHub 登录时不应报错阻断 |
| B3 | `src/platform/github/common/octoKitServiceImpl.ts` | 3处 `throw PermissiveAuthRequiredError` → `return []` | 无认证时返回空数组而非抛异常 |
| B4 | `src/extension/common/constants.ts` | `EXTENSION_ID` → `Community.copilot-chat-nologin` | 区分原版和 NoLogin 版 |
| B5 | `src/platform/env/vscode/envServiceImpl.ts` | plugin name → `copilot-chat-nologin` | 同上 |
| B6 | `src/platform/log/vscode/outputChannelLogTarget.ts` | `OutputChannelName` → `Copilot Chat NoLogin` | 同上 |
| B7 | `src/extension/chat/vscode-node/hooksOutputChannel.ts` | hooks channel → `Copilot Chat NoLogin Hooks` | 同上 |
| B8 | `.vscodeignore` | 加 `!l10n/bundle.l10n.json` | 确保 i18n 资源打包进 VSIX |

### B9: contextKeys.contribution.ts 额外改动（4处）

**问题：** no-auth 用户触发 \_onAuthenticationChange\ 时，多个异步方法未 await 且无 try/catch，可能导致未处理的 Promise 拒绝，干扰 VS Code 聊天存储。

**改动：**
1. \_onAuthenticationChange\ — 所有异步调用加 \wait\ + \	ry/catch\
2. \_updateQuotaExceededContext\ — no-auth 用户直接跳过，设 quotaExceeded = false
3. \_updatePreviewFeaturesDisabledContext\ — no-auth 用户直接跳过
4. \_updatePermissiveSessionContext\ — no-auth 用户跳过 GitHub session 检查

### C类：复杂逻辑改动（冲突风险较高）

| # | 文件 | 改动 | 原因 |
|---|------|------|------|
| C1 | `src/extension/conversation/vscode-node/languageModelAccess.ts` | +44行：no-login 时只显示 BYOK 模型、fallback 到 allEndpoints、auth 变化不清空模型 | 核心：让模型选择器只显示用户自己配置的模型 |
| C2 | `src/extension/contextKeys/vscode-node/contextKeys.contribution.ts` | -28行：删除错误类型判断，统一设为 `Activated` | 让扩展在任何认证失败情况下都能激活 |
| C3 | `src/extension/byok/vscode-node/customOAIProvider.ts` | +41行：`getAllModels` fallback 读 `chatLanguageModels.json` | VS Code 有时不传 configuration，需要直接读配置文件 |
| C4 | `src/extension/byok/vscode-node/azureProvider.ts` | -51行：检查 `apiKey`，无 key 时 throw 而非触发 OAuth | 避免弹出 Microsoft 登录框 |

---

## 每个文件的详细改动说明

### C1: languageModelAccess.ts（最重要，最容易冲突）

**原始逻辑：**
- 无 session 时返回缓存模型
- `onDidAuthenticationChange` 清空 `_currentModels`
- `_getEndpointForModel` 只查 `_chatEndpoints`

**NoLogin 逻辑：**
- 无 session 也继续执行（trace log）
- `isNoLogin` 模式下 `chatEndpoints` 只保留 `isBYOKModel` 的
- auto endpoint 也要过滤
- model picker 不显示分类标题
- `_getEndpointForModel` 先查 `_chatEndpoints`，找不到再查 `allEndpoints`

**关键变量：** `isNoLogin = !copilotToken || copilotToken.isNoAuthUser`

### C2: contextKeys.contribution.ts

**原始逻辑：** 根据错误类型（NotSignedUp、SubscriptionExpired、EnterpriseManaged 等）设置不同的 context key，导致扩展显示不同的错误页面。

**NoLogin 逻辑：** 无论什么错误，统一设置 `key = welcomeViewContextKeys.Activated`，让扩展正常激活。只保留日志。

### C3: customOAIProvider.ts

**原始逻辑：** `getAllModels` 只用 VS Code 传入的 `configuration.models`。

**NoLogin 逻辑：** 如果 `configuration.models` 为空，fallback 直接读 `%APPDATA%/Code/User/chatLanguageModels.json`，按 vendor 名匹配。

### C4: azureProvider.ts

**原始逻辑：** 无 apiKey 时尝试 Microsoft OAuth 登录。

**NoLogin 逻辑：** 检查 `model.apiKey || model.configuration?.apiKey`，无 key 直接 throw 错误（不弹登录框）。