#!/usr/bin/env bash
set -e

# 配置
DOWNLOAD_URL="${PAOPAO_INSTALLER_URL:-https://raw.githubusercontent.com/clovery/paopao-ce/refs/heads/main/releases/latest/download}"
INSTALL_DIR="${HOME}/.paopao-installer"
APP_BIN="${INSTALL_DIR}/paopao-installer"

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    case "$arch" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            echo "错误：不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    echo "${os}-${arch}"
}

# 下载二进制文件
download_binary() {
    local arch=$(detect_arch)
    local download_url="${DOWNLOAD_URL}/paopao-installer-${arch}"
    local temp_file="${INSTALL_DIR}/paopao-installer.tmp"
    
    echo "检测到系统架构: $arch"
    echo "正在从远程下载 paopao-installer..."
    echo "下载地址: $download_url"
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 检查是否有 curl 或 wget
    if command -v curl >/dev/null 2>&1; then
        if ! curl -L -f -o "$temp_file" "$download_url"; then
            echo "错误：下载失败，请检查网络连接或下载地址"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -O "$temp_file" "$download_url"; then
            echo "错误：下载失败，请检查网络连接或下载地址"
            exit 1
        fi
    else
        echo "错误：需要 curl 或 wget 来下载文件"
        exit 1
    fi
    
    # 设置执行权限
    chmod +x "$temp_file"
    
    # 移动到最终位置
    mv "$temp_file" "$APP_BIN"
    
    echo "下载完成: $APP_BIN"
}

# 检查是否需要下载（强制下载或文件不存在）
if [ "${FORCE_DOWNLOAD:-0}" = "1" ] || [ ! -f "$APP_BIN" ]; then
    if [ "${FORCE_DOWNLOAD:-0}" = "1" ]; then
        echo "强制重新下载..."
        rm -f "$APP_BIN"
    fi
    download_binary
else
    echo "使用已存在的二进制文件: $APP_BIN"
fi

# 使用固定端口
PORT=18000

# 清理函数：杀掉进程和释放端口
cleanup() {
    echo ""
    echo "正在清理..."
    
    # 如果进程还在运行，杀掉它
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "正在停止安装服务进程 (PID: $PID)..."
        kill "$PID" 2>/dev/null || true
        sleep 1
        # 如果还没死，强制杀掉
        if kill -0 "$PID" 2>/dev/null; then
            kill -9 "$PID" 2>/dev/null || true
        fi
    fi
    
    # 通过端口查找并杀掉占用端口的进程（双重保险）
    if command -v lsof >/dev/null 2>&1; then
        PORT_PID=$(lsof -ti:$PORT 2>/dev/null || true)
        if [ -n "$PORT_PID" ]; then
            echo "正在释放端口 $PORT (PID: $PORT_PID)..."
            kill "$PORT_PID" 2>/dev/null || true
            sleep 1
            if kill -0 "$PORT_PID" 2>/dev/null; then
                kill -9 "$PORT_PID" 2>/dev/null || true
            fi
        fi
    elif command -v fuser >/dev/null 2>&1; then
        fuser -k "$PORT/tcp" 2>/dev/null || true
    fi
    
    echo "清理完成"
}

# 注册清理函数，捕获退出信号
trap cleanup EXIT INT TERM

echo "使用端口: $PORT"
echo "启动安装服务..."

# 启动 Go 安装器
$APP_BIN \
  --port "$PORT" &

PID=$!

# 自动打开浏览器（如果环境支持）
URL="http://127.0.0.1:$PORT"

if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" >/dev/null 2>&1 || true
elif command -v open >/dev/null 2>&1; then
  open "$URL" >/dev/null 2>&1 || true
else
  echo "请在浏览器中打开：$URL"
fi

echo "等待用户完成安装..."
wait $PID || true

# 清除 trap，因为正常退出时不需要清理
trap - EXIT INT TERM

# 可选：注册 systemd 服务
# cat >/etc/systemd/system/myapp.service <<EOF
# [Unit]
# Description=MyApp Service
#
# [Service]
# ExecStart=/usr/local/bin/myapp
# Restart=always
#
# [Install]
# WantedBy=multi-user.target
# EOF
#
# systemctl daemon-reload
# systemctl enable --now myapp

echo "安装完成！"
