# xiaohongshu-mcp 安装指南

xiaohongshu-mcp 是小红书操作的核心服务，提供搜索、发布、评论、登录等 API。skill 通过它与小红书交互。

## 安装

### macOS

```bash
# 方式一：Homebrew（推荐）
brew install xiaohongshu-mcp

# 方式二：手动下载
# 从项目 Release 页下载对应架构的二进制文件
mkdir -p ~/.local/bin
mv xiaohongshu-mcp ~/.local/bin/
chmod +x ~/.local/bin/xiaohongshu-mcp
```

### Linux

```bash
mkdir -p ~/.local/bin
curl -L -o ~/.local/bin/xiaohongshu-mcp <release-url>
chmod +x ~/.local/bin/xiaohongshu-mcp
```

### 验证安装

```bash
xiaohongshu-mcp --version
# 或通过 skill 脚本检查
bash scripts/xhs.sh status
```

## 首次登录

MCP 需要小红书登录态（cookies）才能操作。

### 步骤

1. **启动 MCP 服务**
   ```bash
   bash scripts/xhs.sh status
   ```
   如果提示未运行，会自动尝试启动。

2. **获取登录二维码**
   ```bash
   bash scripts/xhs.sh login
   ```
   输出一个二维码链接。

3. **用小红书 APP 扫码**
   打开小红书 APP → 扫描二维码 → 确认登录。

4. **验证登录成功**
   ```bash
   bash scripts/xhs.sh status
   ```
   应显示登录用户信息。

## 登录过期

cookies 有效期通常为数天到数周。过期后：

- **自动检测**：系统每 4 小时运行 `keepalive.py` 检查登录状态
- **自动提醒**：过期时会自动推送二维码到 Telegram
- **手动续登**：`bash scripts/xhs.sh login` → 扫码

## 配置

MCP 默认运行在 `http://localhost:18060`。如需更改：

```bash
# 在 config/runtime.env 中设置
MCP_URL=http://你的地址:端口
```

## Cookie 手动注入（备选方案）

如果二维码登录不成功（如提示"已进入注销流程"），可以手动注入浏览器 Cookie：

### 步骤

1. **在浏览器中登录小红书**
   - 打开 https://www.xiaohongshu.com 并登录

2. **导出 Cookie**
   - 打开开发者工具（Command+Option+I）
   - 切到 Network 面板
   - 刷新页面
   - 点击任意 xiaohongshu.com 请求
   - 在 Request Headers 中找到 `cookie:` 行，完整复制

3. **转换为 cookies.json**
   将 cookie 字符串转换为 JSON 数组格式（每个 cookie 一个对象），保存到 `~/cookies.json`：
   ```json
   [
     {"name": "a1", "value": "xxx", "domain": ".xiaohongshu.com", "path": "/", "expires": 1807785435, "httpOnly": false, "secure": false},
     {"name": "web_session", "value": "xxx", "domain": ".xiaohongshu.com", "path": "/", "expires": 1807785435, "httpOnly": true, "secure": true}
   ]
   ```

4. **重启 MCP 服务**
   MCP 启动时会自动读取 `~/cookies.json`。

### 注意事项
- Cookie 有效期通常为数天到数周
- 过期后需要重新从浏览器获取
- `web_session` 和 `id_token` 是最关键的字段

## 常见问题

**Q: MCP 启动失败？**
- 检查端口是否被占用：`lsof -i :18060`
- 检查二进制是否有执行权限：`ls -la ~/.local/bin/xiaohongshu-mcp`

**Q: cookies 文件在哪？**
- 默认位置：`~/.xiaohongshu/cookies.json` 或 `~/cookies.json`
- 自定义位置：设置环境变量 `XHS_COOKIES_SRC=/path/to/cookies.json`

**Q: 远程服务器上怎么扫码？**
- `bash scripts/xhs.sh login` 会输出一个 URL
- 在手机浏览器打开该 URL，然后用小红书 APP 扫描
- 或配置好 Telegram Bot 后，二维码会自动推送到 Telegram
