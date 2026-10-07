# sing-box

自用 VLESS + REALITY 安装脚本。安装后输出 VLESS 链接、Mihomo 和 sing-box 单节点配置。

默认端口 `443`，伪装域名 `itunes.apple.com`，指纹 `chrome`。UUID v4、REALITY 密钥和短 ID 自动生成。

## 安装

需要 Linux、root 权限、systemd，以及 apt-get 或 yum。服务器需能访问 GitHub 和软件源。

以 root 用户运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/irasutoya/sing-box/main/install.sh)
```

指定参数时，下载后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/irasutoya/sing-box/main/install.sh -o install.sh
sudo bash install.sh -port 8443
```

支持架构：amd64、arm64、armv7、armv6、386、mips64le、mipsle、ppc64le、riscv64、s390x、loong64。

## 参数

```text
用法：bash install.sh [选项]

  -port        监听端口（1–65535，默认 443）
  -uuid        UUID v4（默认自动生成）
  -uninstall   卸载并删除程序、配置
  -help        显示帮助
```

`-port`、`-uuid` 后需填写值。端口按十进制处理，`00443` 等同于 `443`。

UUID v4 格式：`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`。`x` 为十六进制字符，`y` 为 `8`、`9`、`a` 或 `b`，不区分大小写。

```bash
sudo bash install.sh -port 8443 -uuid 01234567-89ab-4def-8123-456789abcdef
```

## 客户端

以下为输出模板，`${...}` 在安装时替换为实际值。公网 IP 获取失败时，导入前将 `localhost` 替换为服务器 IP。

### VLESS

```
vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&publicKey=${PUBLIC_KEY}&shortId=${SHORT_ID}#${SERVER_IP}
```

### Mihomo

```yaml
proxies:
  - name: ${SERVER_IP}
    server: ${SERVER_IP}
    port: ${PORT}
    type: vless
    uuid: ${UUID}
    tls: true
    flow: xtls-rprx-vision
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    servername: ${DOMAIN}
    client-fingerprint: chrome
    network: tcp
```

### sing-box

```json
{
  "outbounds": [
    {
      "type": "vless",
      "tag": "${SERVER_IP}",
      "server": "${SERVER_IP}",
      "server_port": ${PORT},
      "uuid": "${UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "${PUBLIC_KEY}",
          "short_id": "${SHORT_ID}"
        }
      }
    }
  ]
}
```

## 管理

```bash
# 状态
systemctl status sing-box

# 日志
journalctl -u sing-box -n 50 --no-pager

# 重启
systemctl restart sing-box

# 帮助
bash install.sh -help

# 卸载
sudo bash install.sh -uninstall
```

- 程序：`/root/sing-box/bin/sing-box`
- 配置：`/root/sing-box/config/config.json`
- 服务：`/etc/systemd/system/sing-box.service`

重复安装会覆盖配置并生成新密钥，客户端需同步更新。卸载会删除程序和配置，需要保留时先备份。

安装失败时检查终端报错；无法连接时检查服务状态、防火墙和安全组的监听端口。
