# 图像生成 Provider 切换指南（v3.0+）

> 薯灵 v3.0 支持两个图像生成 provider：Gemini（默认）和 OpenAI gpt-image-2。
> 两者通过 `IMAGE_GEN_PROTOCOL` 环境变量切换，无需改代码。

## 一览

| Provider | 协议 | 默认模型 | API endpoint | 推荐场景 |
|---|---|---|---|---|
| **Gemini**（默认） | `gemini-native` | `gemini-3-pro-image-preview` | `generativelanguage.googleapis.com` | 中文渲染稳定；免费额度大；亚洲访问快 |
| **OpenAI** | `openai-images` | `gpt-image-2` | `api.openai.com` | 全球可达；付费稳定；prompt rewrite 机制聪明 |
| **通用代理** | `openai-chat` | 用户配 | 用户配 | 高级 — 反代 / 中转 |

## 切换到 Gemini（默认状态）

```bash
python3 agent/scripts/image.py --set-key "<GEMINI_KEY>" --provider gemini
python3 agent/scripts/image.py --check
```

或手工编辑 `agent/config/runtime.env`：
```bash
IMAGE_GEN_PROTOCOL=gemini-native
IMAGE_GEN_MODEL=gemini-3-pro-image-preview
IMAGE_GEN_API_KEY=<KEY>
```

## 切换到 OpenAI gpt-image-2

```bash
python3 agent/scripts/image.py --set-key "sk-..." --provider openai
python3 agent/scripts/image.py --check
```

或手工编辑 `agent/config/runtime.env`：
```bash
IMAGE_GEN_PROTOCOL=openai-images
IMAGE_GEN_MODEL=gpt-image-2
IMAGE_GEN_API_KEY=sk-...
# IMAGE_GEN_BASE_URL=https://api.openai.com   # 默认值，可省
```

## 验证切换成功

```bash
python3 agent/scripts/image.py --check
# 输出含 protocol=openai-images model=gpt-image-2 表示切换生效
```

## 实测建议

切换后用一张测试图验证（不影响真实创作流程）：

```bash
python3 agent/scripts/image.py "测试图：一只猫坐在窗台" /tmp/test.png
ls -la /tmp/test.png   # 应为 PNG 文件
```

## 行为差异

| 维度 | Gemini 3 Pro | gpt-image-2 |
|---|---|---|
| 中文文字渲染 | ✅ 稳 | ⚠ 可能塌（OpenAI 自动 rewrite 时把中文转英文）|
| 参考图（image-to-image） | ✅ inlineData base64 | ✅ /v1/images/edits multipart |
| 推荐 prompt | 中文锚词模板（image_prompt.txt 现版本） | 中文 prompt 也可，但 OpenAI 会做 prompt rewriting |
| 速度 | 5-15s | 10-30s |
| 成本 | 免费额度内免费 | 按 token 计费（gpt-image-2 较贵） |
| 全球可达性 | 中国大陆需代理 | 中国大陆需代理（部分国家原生可达） |

## 故障

- Gemini 报 INVALID_ARGUMENT → 通常是 prompt 含敏感词，让 AI 助手重写 prompt
- OpenAI 报 content_policy_violation → 同上
- 切换后 `--check` 仍报旧 protocol → 检查 runtime.env，可能 `IMAGE_GEN_PROTOCOL` 行被注释了

详细灾难恢复 → [`disaster-recovery.md`](disaster-recovery.md)
