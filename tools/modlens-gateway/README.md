# ChatCube ModLens Gateway

这个伴随进程把手机端当前会话中的图片交给 [ModLens](https://github.com/liustack/modlens)，并将结构化视觉证据返回给 XCube 的 `vision_read_image` 工具。手机应用本身不能运行 Node.js，因此网关需运行在电脑或服务器上。

## 启动

要求 Node.js 22.19 或更高版本。

```bash
cd tools/modlens-gateway
npm install

# 首次使用时按 ModLens 文档配置一个视觉 provider
npx modlens config init
# 例如：npx modlens config set gemini-api.apiKey <your-key>
#       npx modlens config set provider gemini-api

npm start
```

默认只监听 `127.0.0.1:8787`。本机模拟器可配置 `http://127.0.0.1:8787`；真机需让电脑与手机位于可信网络，并监听电脑的局域网地址：

```bash
MODLENS_GATEWAY_HOST=0.0.0.0 \
MODLENS_GATEWAY_TOKEN='请替换为足够长的随机令牌' \
npm start
```

然后在 XCube「设置 → 工具中心 → ModLens 视觉理解」中填写 `http://电脑局域网IP:8787` 与相同令牌。非回环地址未设置令牌时，网关会拒绝启动。

## 接口与安全

- `GET /health`：检查网关和已安装的 ModLens 版本。
- `POST /analyze`：接收一张 base64 图片和可选关注点，内部调用固定版本的 ModLens CLI。
- `POST /auth/login`：可选的单账号登录接口，校验密码派生哈希后签发短时 Bearer；不会向前端暴露主令牌或 provider 密钥。
- 单张图片最大 25 MiB，只接受经文件签名识别的 JPEG、PNG、GIF、WebP。
- 图片仅写入权限为 `0600` 的临时目录，请求结束即删除；HTTP 响应禁止缓存。
- 图片会继续发送给你在 ModLens 中选择的视觉 provider。不要对不受信网络直接暴露此端口；跨公网部署时应在前面配置 HTTPS 反向代理。

环境变量：

| 名称 | 默认值 | 用途 |
|---|---:|---|
| `MODLENS_GATEWAY_HOST` | `127.0.0.1` | 监听地址 |
| `MODLENS_GATEWAY_PORT` | `8787` | 监听端口 |
| `MODLENS_GATEWAY_TOKEN` | 空 | Bearer 令牌；非回环监听时必填 |
| `MODLENS_AUTH_USERNAME` | 空 | 单账号登录用户名；与下列三项同时配置才会启用登录接口 |
| `MODLENS_AUTH_PASSWORD_SALT` | 空 | scrypt 密码盐的十六进制值 |
| `MODLENS_AUTH_PASSWORD_HASH` | 空 | 64 字节 scrypt 密码哈希的十六进制值；不要保存明文密码 |
| `MODLENS_SESSION_SECRET` | 空 | 至少 32 字节、base64url 编码的会话签名密钥 |
| `MODLENS_SESSION_TTL_SECONDS` | `28800` | 登录 Bearer 有效期，最长 86400 秒 |
| `MODLENS_TIMEOUT_MS` | `180000` | ModLens 单次分析超时 |
| `MODLENS_MAX_CONCURRENT` | `1` | 最大并发分析数；超过时返回 429，避免耗尽内存或模型额度 |
| `MODLENS_PROVIDER` | 空 | 固定使用指定 provider，例如 `openai`；设置后不自动回退 |
| `MODLENS_WORKDIR` | 网关目录 | ModLens provider 工作目录 |
| `MODLENS_CLI_PATH` | 项目依赖中的 CLI | 自定义 ModLens CLI 路径 |
