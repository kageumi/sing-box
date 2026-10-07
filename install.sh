#!/bin/bash

# sing-box 安装脚本

# 全局变量定义
BASE_DIR="/root/sing-box"
INSTALL_DIR="${BASE_DIR}/bin"
CONFIG_DIR="${BASE_DIR}/config"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DOMAIN="itunes.apple.com"
PORT=443
UUID=""
PRIVATE_KEY=""
PUBLIC_KEY=""
SHORT_ID=""
TEMP_DIR=""

# 颜色定义
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

# 日志函数
log() {
  echo -e "${GREEN}[信息]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[提醒]${NC} $1"
}

error() {
  echo -e "${RED}[错误]${NC} $1"
}

# 显示帮助
show_help() {
  echo -e "${BLUE}sing-box 安装 · VLESS + REALITY${NC}"
  echo -e "用法：$0 [选项]"
  echo
  echo -e "选项："
  echo -e "  ${GREEN}-port${NC}        监听端口（1–65535，默认 443）"
  echo -e "  ${GREEN}-uuid${NC}        UUID v4（默认自动生成）"
  echo -e "  ${GREEN}-uninstall${NC}   卸载并删除程序、配置"
  echo -e "  ${GREEN}-help${NC}        显示帮助"
}

# 参数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    -port)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
        error "端口无效，用法：-port 443（1–65535）"
        exit 1
      fi
      PORT="$2"
      # 先去除前导零并限制长度，避免八进制解释和整数溢出。
      while [[ ${#PORT} -gt 1 && "$PORT" == 0* ]]; do
        PORT="${PORT:1}"
      done
      if [[ ${#PORT} -gt 5 ]] || (( 10#$PORT < 1 || 10#$PORT > 65535 )); then
        error "端口无效，用法：-port 443（1–65535）"
        exit 1
      fi
      shift 2
      ;;
    -uuid)
      if [[ $# -lt 2 || ! "$2" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-4[[:xdigit:]]{3}-[89aAbB][[:xdigit:]]{3}-[[:xdigit:]]{12}$ ]]; then
        error "UUID 无效，-uuid 仅支持 UUID v4"
        exit 1
      fi
      UUID="$2"
      shift 2
      ;;
    -uninstall)
      UNINSTALL=true
      shift
      ;;
    -help)
      show_help
      exit 0
      ;;
    *)
      error "未知参数：$1"
      show_help
      exit 1
      ;;
  esac
done

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  error "需要 root 权限：sudo bash install.sh"
  exit 1
fi

# 卸载函数
uninstall() {
  log "卸载 sing-box…"
  systemctl stop sing-box 2>/dev/null
  systemctl disable sing-box 2>/dev/null
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  rm -rf "$BASE_DIR"
  log "卸载操作结束"
  exit 0
}

# 如果是卸载模式，执行卸载函数
if [ "$UNINSTALL" = true ]; then
  uninstall
fi

# 安装依赖
install_dependencies() {
  log "安装依赖…"
  if command -v apt-get > /dev/null; then
    apt-get update -qq && apt-get install -y -qq curl wget jq openssl || {
      error "依赖安装失败，请检查软件源和网络"
      exit 1
    }
  elif command -v yum > /dev/null; then
    yum install -y -q curl wget jq openssl || {
      error "依赖安装失败，请检查软件源和网络"
      exit 1
    }
  else
    error "系统不支持，需要 apt-get 或 yum"
    exit 1
  fi
  log "依赖已就绪"
}

# 依赖就绪后生成默认 UUID 和短 ID
initialize_config_values() {
  if [[ -z "$UUID" ]]; then
    UUID=$(cat /proc/sys/kernel/random/uuid) || {
      error "UUID 生成失败，可用 -uuid 指定 UUID v4"
      exit 1
    }
    if [[ ! "$UUID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-4[[:xdigit:]]{3}-[89aAbB][[:xdigit:]]{3}-[[:xdigit:]]{12}$ ]]; then
      error "生成的 UUID 无效，请用 -uuid 指定 UUID v4"
      exit 1
    fi
  fi
  SHORT_ID=$(openssl rand -hex 8) || {
    error "短 ID 生成失败，请检查 openssl"
    exit 1
  }
  if [[ -z "$SHORT_ID" ]]; then
    error "短 ID 为空，请检查 openssl"
    exit 1
  fi
}

# 检测系统架构
determine_architecture() {
  log "检测架构…"
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    armv6l) ARCH="armv6" ;;
    i386 | i686) ARCH="386" ;;
    mips64le) ARCH="mips64le" ;;
    mipsle) ARCH="mipsle" ;;
    ppc64le) ARCH="ppc64le" ;;
    riscv64) ARCH="riscv64" ;;
    s390x) ARCH="s390x" ;;
    loongarch64) ARCH="loong64" ;;
    *)
      error "不支持的架构：$ARCH"
      exit 1
      ;;
  esac
  log "架构：$ARCH"
}

# 安装 sing-box
install_sing_box() {
  log "准备安装…"
  mkdir -p "$INSTALL_DIR" || {
    error "安装目录创建失败：$INSTALL_DIR"
    exit 1
  }

  # 获取最新版本
  VERSION_RESPONSE=$(curl -fsS --connect-timeout 5 --max-time 10 https://api.github.com/repos/SagerNet/sing-box/releases/latest) &&
    LATEST_VERSION=$(printf '%s' "$VERSION_RESPONSE" | jq -r .tag_name) || LATEST_VERSION=""
  if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
    warn "版本查询失败，尝试备用查询…"
    VERSION_RESPONSE=$(curl -fsS --connect-timeout 5 --max-time 10 https://api.github.com/repos/SagerNet/sing-box/tags) &&
      LATEST_VERSION=$(printf '%s' "$VERSION_RESPONSE" | jq -r '.[0].name') || LATEST_VERSION=""
    
    if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
      error "版本查询失败，请检查 GitHub 连接"
      exit 1
    fi
  fi

  DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION:1}-linux-${ARCH}.tar.gz"
  log "下载 sing-box ${LATEST_VERSION}（${ARCH}）…"

  # 下载并解压
  TEMP_DIR=$(mktemp -d /tmp/sing-box.XXXXXXXXXX) || {
    error "临时目录创建失败，请检查 /tmp"
    exit 1
  }
  wget -q --timeout=30 --tries=3 -O "$TEMP_DIR/sing-box.tar.gz" "$DOWNLOAD_URL" || {
    error "下载失败，请检查 GitHub 连接"
    exit 1
  }
  
  # 验证下载文件
  if [ -s "$TEMP_DIR/sing-box.tar.gz" ]; then
    log "解压安装包…"
  else
    error "安装包为空，请重新下载"
    exit 1
  fi

  tar -xzf "$TEMP_DIR/sing-box.tar.gz" -C "$TEMP_DIR" || {
    error "解压失败，请检查安装包和磁盘空间"
    exit 1
  }

  # 移动文件并清理
  mv "$TEMP_DIR/sing-box-${LATEST_VERSION:1}-linux-${ARCH}/sing-box" "$INSTALL_DIR/sing-box" || {
    error "程序安装失败：$INSTALL_DIR"
    exit 1
  }

  cleanup_temp_files
  chmod +x "$INSTALL_DIR/sing-box" || {
    error "执行权限设置失败：$INSTALL_DIR/sing-box"
    exit 1
  }
  log "程序：$INSTALL_DIR/sing-box"
}

# 生成 REALITY 密钥对
generate_reality_keypair() {
  log "生成 REALITY 密钥…"
  if ! REALITY_KEYPAIR=$("$INSTALL_DIR/sing-box" generate reality-keypair); then
    error "REALITY 密钥生成失败"
    exit 1
  fi
  PRIVATE_KEY=$(echo "$REALITY_KEYPAIR" | grep "PrivateKey" | awk '{print $2}' | tr -d '"')
  PUBLIC_KEY=$(echo "$REALITY_KEYPAIR" | grep "PublicKey" | awk '{print $2}' | tr -d '"')
  if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    error "REALITY 密钥不完整"
    exit 1
  fi
  log "REALITY 密钥已生成"
}

# 创建配置文件
create_config_file() {
  log "保存配置…"
  mkdir -p "$CONFIG_DIR" || {
    error "配置目录创建失败：$CONFIG_DIR"
    exit 1
  }
  if ! cat > "$CONFIG_FILE" <<EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${DOMAIN}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": "${SHORT_ID}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF
  then
    error "配置保存失败：$CONFIG_FILE"
    exit 1
  fi
  log "配置：$CONFIG_FILE"
}

# 创建 systemd 服务
create_systemd_service() {
  log "设置系统服务…"
  if ! cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=sing-box
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  then
    error "服务文件保存失败：$SERVICE_FILE"
    exit 1
  fi

  systemctl daemon-reload || {
    error "服务加载失败：systemctl daemon-reload"
    exit 1
  }
  log "服务：$SERVICE_FILE"
}

# 打印客户端配置
print_client_config() {
  log "获取公网 IP…"
  SERVER_IP=$(curl -fsS --connect-timeout 5 --max-time 10 https://api.ipify.org) || SERVER_IP=""
  if [[ -z "$SERVER_IP" ]]; then
    warn "公网 IP 获取失败，导入前将 localhost 替换为服务器 IP"
    SERVER_IP="localhost"
  fi

  VLESS_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&publicKey=${PUBLIC_KEY}&shortId=${SHORT_ID}#${SERVER_IP}"
  MIHOMO_CONFIG="proxies:
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
    network: tcp"

  # 打印配置信息
  echo
  echo -e "${BLUE}── VLESS ──${NC}"
  echo "$VLESS_URL"
  echo
  echo -e "${BLUE}── Mihomo ──${NC}"
  echo -e "$MIHOMO_CONFIG"
  echo
  echo -e "${BLUE}── sing-box ──${NC}"
  cat <<EOF
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
EOF
  echo
}

start_service() {
  local service_enabled=true
  log "启动服务…"
  systemctl start sing-box || {
    error "启动失败，查看日志：journalctl -u sing-box -n 50 --no-pager"
    exit 1
  }

  systemctl enable sing-box || {
    service_enabled=false
    warn "自启设置失败，重试：systemctl enable sing-box"
  }

  # 检查服务状态
  if systemctl is-active --quiet sing-box; then
    if [[ "$service_enabled" == true ]]; then
      log "服务已启动，已开启自启"
    else
      log "服务已启动，未能设置自启"
    fi
  else
    error "服务未运行，查看日志：journalctl -u sing-box -n 50 --no-pager"
    exit 1
  fi
}

# 仅清理本次安装创建的临时目录
cleanup_temp_files() {
  if [[ -n "$TEMP_DIR" ]]; then
    if rm -rf -- "$TEMP_DIR"; then
      TEMP_DIR=""
    else
      warn "临时目录清理失败：$TEMP_DIR"
    fi
  fi
}

# 处理中断信号
cleanup() {
  echo
  warn "安装中断，清理临时文件…"
  exit 1
}

# 设置中断处理
trap cleanup INT TERM
trap cleanup_temp_files EXIT

# 主函数
main() {
  log "安装 sing-box · VLESS + REALITY"
  install_dependencies
  initialize_config_values
  determine_architecture
  install_sing_box
  generate_reality_keypair
  create_config_file
  create_systemd_service
  start_service
  log "安装完成：$BASE_DIR"
  print_client_config
}

# 执行主函数
main
