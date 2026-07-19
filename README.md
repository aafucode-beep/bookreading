# 勇敢成长 · 绘本伴读 App

“勇敢成长”面向 4 岁儿童及家长：家长拍摄纸质绘本，服务端分析页序、标题、简介和双语内容，Android App 负责朗读、自动翻页、选页阅读与离线缓存。

## 项目组成

```text
mobile/       Flutter Android 客户端
server/       FastAPI、SQLite、后台任务、AI/TTS 供应商与测试
deploy/       Caddy HTTPS 配置
scripts/      本地开发与签名 APK 发布脚本
compose.yaml  VPS 的 Docker Compose 编排
```

运行架构：公网只访问 Caddy；Caddy 将 HTTPS 请求反向代理给内部 FastAPI。API、worker 和 backup 共享 VPS 上的持久化目录，SQLite、绘本图片和音频不进入 Git。

## 一、VPS 前置条件

推荐 Ubuntu 22.04 或 24.04，至少 2 核 CPU、2GB 内存，并准备：

- 一个指向 VPS 公网 IP 的域名，例如 `books.example.com`。
- GitHub 私有仓库 `yjhkrepo/bookreading` 的只读 Deploy Key。
- MiniMax Token Plan 与 OpenAI API 凭据。
- 能使用 `sudo` 的 VPS 账号。

先在域名服务商处添加 A 记录；如果 VPS 配置了 IPv6，再添加 AAAA 记录。等待 DNS 生效后再启动 Caddy，否则无法申请 HTTPS 证书。

## 二、VPS 需要开放的端口

| 端口 | 协议 | 是否公网开放 | 用途 |
|---|---|---:|---|
| SSH 端口，默认 22 | TCP | 仅允许你的管理 IP | 登录和维护 VPS |
| 80 | TCP | 是 | HTTP 跳转及 HTTPS 证书签发 |
| 443 | TCP | 是 | App、管理后台和 APK 的 HTTPS 访问 |
| 443 | UDP | 建议 | Caddy HTTP/3 |
| 8000 | TCP | 否 | FastAPI 仅在 Docker 内部使用 |

不要公开 SQLite、Docker API、FastAPI 8000 端口或任何数据库端口。先放行 SSH，再启用防火墙，避免把自己锁在 VPS 外：

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw enable
sudo ufw status verbose
```

如果 SSH 使用自定义端口，先执行 `sudo ufw allow 你的端口/tcp`，再启用 UFW。云服务商还有安全组时，也要开放相同端口。

## 三、安装 Docker Engine 与 Compose

以下命令使用 Docker 官方 Ubuntu 软件源：

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

退出 SSH 并重新登录，让 `docker` 用户组生效，然后验证：

```bash
docker version
docker compose version
```

Docker 官方安装参考：<https://docs.docker.com/engine/install/ubuntu/>

## 四、为私有 GitHub 仓库配置只读 Deploy Key

在 VPS 生成这一个仓库专用的 SSH 密钥，不要设置写权限：

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "bookreading-vps" \
  -f ~/.ssh/bookreading_deploy -N ""
cat ~/.ssh/bookreading_deploy.pub
```

复制输出的公钥，在 GitHub 打开：

```text
yjhkrepo/bookreading
→ Settings
→ Deploy keys
→ Add deploy key
```

名称填写 `bookreading-vps`，粘贴公钥，不要勾选 `Allow write access`。

在 VPS 写入 SSH 主机配置：

```bash
cat >> ~/.ssh/config <<'EOF'
Host github-bookreading
  HostName github.com
  User git
  IdentityFile ~/.ssh/bookreading_deploy
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config ~/.ssh/bookreading_deploy

ssh -T github-bookreading
```

首次连接确认 GitHub 主机指纹后，克隆仓库：

```bash
cd /opt
sudo mkdir -p bookreading
sudo chown "$USER":"$USER" bookreading
git clone git@github-bookreading:yjhkrepo/bookreading.git bookreading
cd bookreading
```

GitHub Deploy Key 参考：<https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys>

## 五、创建生产环境配置

`.env` 永远只存在 VPS，不上传 GitHub：

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

至少修改以下内容：

```dotenv
DOMAIN=books.example.com
ENVIRONMENT=production
PUBLIC_BASE_URL=https://books.example.com
SECRET_KEY=请替换为随机密钥

AI_MODE=live
PREFERRED_PROVIDER=minimax

MINIMAX_API_KEY=你的MiniMax订阅Key
MINIMAX_MODEL=你启用的模型ID

OPENAI_API_KEY=你的OpenAI密钥
OPENAI_VISION_MODEL=你启用的视觉模型ID
```

生成 `SECRET_KEY`：

```bash
openssl rand -hex 48
```

把生成结果填入 `.env`，不要把结果粘贴到聊天、命令历史或 GitHub。模型 ID 和密钥仅由 VPS 容器读取，不会下发到 Android App。

如需先验证部署而不调用真实 AI，可临时设置 `AI_MODE=mock`；验证后改回 `AI_MODE=live` 并重启服务。

## 六、创建持久化目录

容器以内置 UID `10001` 运行。首次启动前创建目录并授予写权限：

```bash
mkdir -p server/data server/backups server/downloads
sudo chown -R 10001:10001 \
  server/data server/backups server/downloads
```

这些目录保存数据库、绘本、音频、备份和 APK，已被 `.gitignore` 排除，执行 `git pull` 不会覆盖。

## 七、构建并启动服务器

先检查 Compose 展开结果，再构建：

```bash
docker compose config
docker compose pull
docker compose up -d --build
docker compose ps
```

服务包含：

- `caddy`：公网 HTTPS、证书及反向代理。
- `api`：FastAPI、登录、上传、书架、媒体和运维后台。
- `worker`：图片分析、翻译、完整性判断和 TTS。
- `backup`：每天创建 SQLite 与媒体归档，保留 7 个日备份和 4 个周备份。

创建唯一的家长账号：

```bash
docker compose exec api \
  python -m app.cli create-admin --username parent
```

命令会交互式要求输入家长密码与 4 位 PIN，不要把密码写入 Git 或 shell 脚本。

## 八、验证服务

```bash
docker compose ps
curl -fsS "https://${DOMAIN}/health"
docker compose logs --tail=100 api
docker compose logs --tail=100 worker
docker compose logs --tail=100 caddy
```

健康检查应返回：

```json
{"status":"ok","service":"勇敢成长","ai_mode":"live"}
```

浏览器访问：

```text
https://你的域名/          APK 下载页
https://你的域名/admin    家长运维后台
```

如果证书申请失败，检查域名 DNS、云安全组、UFW，以及 80/443 是否被其他程序占用：

```bash
sudo ss -lntup | grep -E ':80|:443'
docker compose logs caddy
```

## 九、发布 Android APK

正式 APK 应在本地安全环境签名，不要把 keystore、`key.properties` 或签名密码上传 GitHub。

本地配置 `mobile/android/key.properties` 后运行：

```powershell
.\scripts\publish-apk.ps1
```

脚本先运行 Flutter 测试和静态分析，再输出：

```text
server/downloads/brave-growth.apk
server/downloads/brave-growth.apk.sha256
```

将 APK 单独复制到 VPS：

```powershell
scp .\server\downloads\brave-growth.apk `
  用户名@VPS地址:/opt/bookreading/server/downloads/
```

然后在 VPS 执行：

```bash
sudo chown 10001:10001 server/downloads/brave-growth.apk
```

APK 下载地址：

```text
https://你的域名/downloads/brave-growth.apk
```

## 十、后续更新流程

在本地修改、测试并推送到 GitHub 后，VPS 执行：

```bash
cd /opt/bookreading
git pull --ff-only
docker compose config
docker compose up -d --build
docker compose ps
```

查看服务状态：

```bash
docker compose logs -f --tail=100 api worker caddy
```

如果只修改 `.env`：

```bash
docker compose up -d --force-recreate
```

不要执行 `docker compose down -v`，它会删除 Caddy 的命名卷。日常更新也不要删除 `server/data`、`server/backups` 或 `server/downloads`。

## 十一、本地开发与测试

服务端：

```powershell
cd server
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"
$env:AI_MODE="mock"
.\.venv\Scripts\python.exe -m pytest -p no:cacheprovider
.\.venv\Scripts\python.exe -m ruff check --no-cache app tests
```

Flutter：

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

测试样本由程序生成，不包含第三方绘本素材。

## 安全约束

- 只提交 `.env.example`，绝不提交 `.env` 或其他 `.env.*`。
- 不提交 GitHub Token、AI Key、数据库、绘本、音频、备份或 APK。
- 不提交 Android keystore、`key.properties`、PEM、P12 或 PFX 文件。
- VPS 使用只读 Deploy Key；本地推送使用 GitHub CLI/Windows Keyring。
- `.env` 权限保持 `600`，SSH 仅向管理 IP 开放。

