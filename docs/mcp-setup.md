# xiaohongshu-mcp 安装指南

> `xiaohongshu-mcp` 是薯灵的核心依赖，提供搜索、发布、评论、登录等 API。skill 通过 `scripts/xhs.sh` 调用它与小红书交互。源码仓库：[xpzouying/xiaohongshu-mcp](https://github.com/xpzouying/xiaohongshu-mcp)。

---

## 30 秒速检

```bash
# 端口是否被占用？服务是否在跑？登录态是否有效？
lsof -i :18060
bash scripts/xhs.sh status
```

如果三项都正常，跳到 [首次登录](#首次登录)。否则按下面的"完整安装"走。

---

## 完整安装

`xiaohongshu-mcp` 是 Go 编写的 HTTP 服务（默认监听 `:18060`）。三种装法任选：

### 方式 A：源码编译（推荐，跨平台通用）

前置：Go 1.21+

```bash
# 1. 安装 Go
# macOS:  brew install go
# Linux:  sudo apt install -y golang   或  https://go.dev/dl/

# 2. 克隆并编译
git clone https://github.com/xpzouying/xiaohongshu-mcp.git
cd xiaohongshu-mcp
go build -o xiaohongshu-mcp ./cmd/server   # 产物默认叫 server/main，按仓库 README 为准

# 3. 放到 PATH
mkdir -p ~/.local/bin
mv xiaohongshu-mcp ~/.local/bin/
chmod +x ~/.local/bin/xiaohongshu-mcp

# 4. 启动（前台跑一次看看日志）
~/.local/bin/xiaohongshu-mcp
# 看到 "listening on :18060" 即成功，Ctrl+C 停止
```

### 方式 B：Release 二进制（如果上游发布了）

> 上游是否发布二进制以 [Releases 页](https://github.com/xpzouying/xiaohongshu-mcp/releases) 为准，没有就走方式 A。

```bash
# macOS Intel
curl -L -o ~/.local/bin/xiaohongshu-mcp \
  https://github.com/xpzouying/xiaohongshu-mcp/releases/latest/download/xiaohongshu-mcp-darwin-amd64
chmod +x ~/.local/bin/xiaohongshu-mcp
```

```bash
# Linux x86_64
curl -L -o ~/.local/bin/xiaohongshu-mcp \
  https://github.com/xpzouying/xiaohongshu-mcp/releases/latest/download/xiaohongshu-mcp-linux-amd64
chmod +x ~/.local/bin/xiaohongshu-mcp
```

### 方式 C：Docker（隔离环境）

```bash
docker run -d --name xhs-mcp \
  -p 18060:18060 \
  -v ~/.xiaohongshu:/root/.xiaohongshu \
  xpzouying/xiaohongshu-mcp:latest
# 镜像名以仓库 README 为准，没有官方镜像就自己 build
```

### 验证

```bash
xiaohongshu-mcp --version || true
curl -s http://localhost:18060/health || echo "服务未起"
bash scripts/xhs.sh status
```

---

## 把它变成常驻服务

前台跑在调试阶段 OK，日常使用要让它在后台长跑。

### macOS：launchd

```bash
cat > ~/Library/LaunchAgents/com.shuling.xhsmcp.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>com.shuling.xhsmcp</string>
  <key>ProgramArguments</key> <array><string>/Users/你/.local/bin/xiaohongshu-mcp</string></array>
  <key>RunAtLoad</key>        <true/>
  <key>KeepAlive</key>        <true/>
  <key>StandardOutPath</key>  <string>/tmp/xhs-mcp.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/xhs-mcp.err.log</string>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.shuling.xhsmcp.plist
launchctl list | grep xhsmcp
```

### Linux：systemd user service

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/xhs-mcp.service <<'EOF'
[Unit]
Description=xiaohongshu-mcp
After=network-online.target

[Service]
ExecStart=%h/.local/bin/xiaohongshu-mcp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now xhs-mcp
systemctl --user status xhs-mcp
```

---

## 首次登录

MCP 需要小红书登录态（cookies）才能操作。**两种方式任选**，用户偏好优先。

### 方式 1：扫码登录（推荐，0 手动操作）

```bash
bash scripts/xhs.sh login
```

输出一个二维码链接（形如 `https://...qrcode.png`）。

- **本地 Mac**：在浏览器打开该链接，用小红书 APP 扫描。
- **远程服务器**：把链接复制到手机浏览器打开再扫。或配 Telegram Bot 让二维码自动推到手机。

扫码确认后：

```bash
bash scripts/xhs.sh status   # 应显示登录用户信息
```

### 方式 2：Cookie 粘贴（扫码失败时）

**适用场景**：扫码提示"已进入注销流程"、"登录失败"、或你已在浏览器登录想直接复用。

#### 2.1 从浏览器提取 Cookie

1. 打开 Chrome / Safari / Firefox，访问 [https://www.xiaohongshu.com](https://www.xiaohongshu.com) 并登录。
2. 打开开发者工具：
   - Chrome / Edge：`Cmd/Ctrl + Option + I` → `Network` 面板
   - Safari：先在「偏好设置 → 高级」勾选"在菜单栏中显示开发菜单"，然后 `Cmd + Option + I` → `Network`
   - Firefox：`Cmd/Ctrl + Option + E` → `Network`
3. **刷新页面**（`Cmd/Ctrl + R`）让请求出现在 Network 列表里。
4. 在列表里找**任意 `xiaohongshu.com` 域名的请求**（通常第一个就是 `www.xiaohongshu.com` 本身）。
5. 点进去，展开 `Request Headers`，找到 `cookie:` 这一行（注意是 request 不是 response）。
6. **完整复制整行 `cookie:` 后面的值**（从第一个 `=` 之前的 key 开始，到最后一个值结束；不要包含 `cookie:` 本身；不要换行）。

> 一键小书签：在浏览器地址栏新建书签，URL 填入 `javascript:void(navigator.clipboard.writeText(document.cookie));alert('已复制')` —— 在 xiaohongshu.com 页面点这个书签会自动把 document.cookie 复制到剪贴板（只包含非 HttpOnly 项，可能不够全，DevTools 法更稳妥）。

#### 2.2 把 Cookie 交给 AI 助手

**最简单**：在 AI 对话里直接说：

> "我给你 cookie：`<你刚复制的字符串>`"

AI 会自动调用：

```bash
bash scripts/xhs.sh import-cookie '<整串 cookie>'
```

#### 2.3 手动命令（跳过 AI）

```bash
bash scripts/xhs.sh import-cookie 'a1=xxx; web_session=yyy; xsecappid=zzz; ...'
bash scripts/xhs.sh status   # 验证
```

---

## 登录过期与续期

Cookie 有效期通常数天到数周。过期后：

- **自动检测**：system 定时跑 `scripts/xhs.sh status`，登录失效会写进 `request_log`（v2.1.1+）
- **重新登录**：`bash scripts/xhs.sh login` 扫码，或重复 [2.2](#22-把-cookie-交给-ai-助手)

---

## 配置

MCP 默认 `http://localhost:18060`。如需更改：

```bash
# 1. 改 config/runtime.env
MCP_URL=http://你的地址:端口

# 或 2. 仅当前会话 export
export XHS_MCP_URL=http://你的地址:端口
```

---

## 常见错误自检表

| 症状 | 可能原因 | 诊断命令 | 修复 |
|---|---|---|---|
| `xhs.sh status` 报 `connection refused` | MCP 未启动 | `lsof -i :18060` | 启动 MCP（见上文"常驻服务"） |
| MCP 启动时报 `bind: address already in use` | 端口被其它进程占 | `lsof -i :18060` | 杀掉占用进程，或改 `XHS_MCP_URL` 端口 |
| `xhs.sh login` 返回的 URL 打不开 | MCP 与外网断开 | `curl https://xiaohongshu.com -I` | 检查代理/防火墙 |
| 扫码后仍 `not logged in` | 账号触发风控 / cookies 被清 | 换 Cookie 粘贴法 | [2.2](#22-把-cookie-交给-ai-助手) |
| `xhs.sh status` 很慢（>10s） | 上游接口延迟 | `time bash scripts/xhs.sh status` | 不影响使用；`preflight.py` 已对超时放宽 |
| `cookies.json` 被改坏 | 手动编辑失误 | `cat ~/.xiaohongshu/cookies.json \| jq .` | 删除文件 → 重新 import-cookie 或扫码 |

---

## 常见问题 FAQ

**Q: 二进制放哪合适？**
推荐 `~/.local/bin`（符合 XDG）。也可 `/usr/local/bin`（需 sudo）。关键是在 `$PATH` 里。

**Q: cookies 文件在哪？**
- 默认：`~/.xiaohongshu/cookies.json` 或 `~/cookies.json`
- 自定义：设 `XHS_COOKIES_SRC=/path/to/cookies.json`

**Q: 远程服务器上扫码？**
- 三条路：(1) 把 URL 复制到手机浏览器扫；(2) 配 Telegram Bot 推到手机；(3) 直接用 Cookie 粘贴法。

**Q: 能不能不装 MCP，让 skill 直接调小红书 API？**
不能。小红书没有公开 API，MCP 靠浏览器会话模拟请求。没有 MCP 就没有"手"。

**Q: 会被封号吗？**
v2.1.0 起默认开启节流 + 日限额（`v1-conservative` profile），对"正常使用强度"安全。但：
- 关节流（`XHS_DISABLE_THROTTLE=1`）是自杀行为
- 短期高频搜索/发布仍可能触风控，本 skill 无法完全规避
