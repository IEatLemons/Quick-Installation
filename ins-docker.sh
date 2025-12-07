#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect if server is in China
detect_region() {
    print_info "正在检测服务器地理位置..."
    
    # Method 1: Check timezone
    TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null || echo "")
    if [[ "$TIMEZONE" == *"Asia/Shanghai"* ]] || [[ "$TIMEZONE" == *"Asia/Chongqing"* ]] || [[ "$TIMEZONE" == *"Asia/Urumqi"* ]]; then
        print_info "检测到时区为中国: $TIMEZONE"
        echo "CN"
        return
    fi
    
    # Method 2: Check IP location (try multiple services)
    IP=$(curl -s --max-time 3 ip.sb 2>/dev/null || curl -s --max-time 3 ifconfig.me 2>/dev/null || curl -s --max-time 3 icanhazip.com 2>/dev/null || echo "")
    
    if [[ -n "$IP" ]]; then
        # Try to get country code from IP
        COUNTRY=$(curl -s --max-time 3 "https://ipapi.co/${IP}/country_code/" 2>/dev/null || \
                  curl -s --max-time 3 "http://ip-api.com/json/${IP}?fields=countryCode" 2>/dev/null | grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4 || \
                  echo "")
        
        if [[ "$COUNTRY" == "CN" ]] || [[ "$COUNTRY" == *"CN"* ]]; then
            print_info "检测到 IP 地址位于中国: $IP"
            echo "CN"
            return
        fi
    fi
    
    # Method 3: Test connection speed to Chinese servers
    print_info "正在测试网络连接速度..."
    SPEED=$(curl -o /dev/null -s --max-time 5 --write-out '%{speed_download}' https://mirrors.aliyun.com 2>/dev/null || echo "0")
    if [[ -n "$SPEED" ]] && (( $(echo "$SPEED > 10000" | bc -l 2>/dev/null || echo 0) )); then
        print_info "检测到连接国内服务器速度较快，将使用国内镜像源"
        echo "CN"
        return
    fi
    
    print_info "未检测到中国服务器，将使用官方源"
    echo "US"
}

# Detect region
REGION=$(detect_region)

# Set mirror sources based on region
if [[ "$REGION" == "CN" ]]; then
    DOCKER_MIRROR="https://mirrors.aliyun.com/docker-ce"
    DOCKER_COMPOSE_MIRROR="https://get.daocloud.io/docker/compose/releases/download"
    GITHUB_MIRROR="https://ghproxy.com/https://github.com"
    print_info "使用国内镜像源（阿里云）"
else
    DOCKER_MIRROR="https://download.docker.com"
    DOCKER_COMPOSE_MIRROR="https://github.com/docker/compose/releases/download"
    GITHUB_MIRROR="https://github.com"
    print_info "使用官方源"
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "请不要使用 root 用户运行此脚本"
    exit 1
fi

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    print_error "未找到 sudo 命令，请先安装 sudo"
    exit 1
fi

print_info "开始安装 Docker 和 Docker Compose..."

# Update package index
print_info "更新软件包列表..."
sudo apt update -y || {
    print_error "更新软件包列表失败"
    exit 1
}

# Install prerequisite packages
print_info "安装必要的依赖包..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release || {
    print_error "安装依赖包失败"
    exit 1
}

# Add Docker's official GPG key
print_info "添加 Docker GPG 密钥..."
if [[ "$REGION" == "CN" ]]; then
    # Use Aliyun mirror for GPG key
    curl -fsSL ${DOCKER_MIRROR}/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || {
        print_warn "从镜像源获取 GPG 密钥失败，尝试使用官方源..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || {
            print_error "添加 GPG 密钥失败"
            exit 1
        }
    }
else
    curl -fsSL ${DOCKER_MIRROR}/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || {
        print_error "添加 GPG 密钥失败"
        exit 1
    }
fi

# Set up the stable Docker repository
print_info "配置 Docker 仓库..."
ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)

echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ${DOCKER_MIRROR}/linux/ubuntu ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || {
    print_error "配置 Docker 仓库失败"
    exit 1
}

# Update the package index again
print_info "更新软件包列表（包含 Docker 仓库）..."
sudo apt update -y || {
    print_error "更新软件包列表失败，可能是仓库配置有问题"
    print_warn "尝试清理并重新配置..."
    sudo rm -f /etc/apt/sources.list.d/docker.list
    exit 1
}

# Install Docker Engine
print_info "安装 Docker Engine..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
    print_error "安装 Docker 失败"
    print_warn "可能的原因："
    print_warn "1. 网络连接问题"
    print_warn "2. 仓库配置问题"
    print_warn "3. 系统版本不兼容"
    exit 1
}

# Enable Docker to start at boot
print_info "设置 Docker 开机自启..."
sudo systemctl enable docker || {
    print_warn "无法设置 Docker 开机自启（可能 Docker 未正确安装）"
}

# Start Docker service
print_info "启动 Docker 服务..."
sudo systemctl start docker || {
    print_error "启动 Docker 服务失败"
    sudo systemctl status docker
    exit 1
}

# Wait a moment for Docker to start
sleep 2

# Verify Docker is running
if sudo systemctl is-active --quiet docker; then
    print_info "Docker 服务运行正常"
else
    print_error "Docker 服务未运行"
    exit 1
fi

# Add current user to the docker group
print_info "将当前用户添加到 docker 组..."
if getent group docker > /dev/null 2>&1; then
    sudo usermod -aG docker $USER || {
        print_warn "无法将用户添加到 docker 组"
    }
else
    print_warn "docker 组不存在，跳过用户组配置"
fi

# Install Docker Compose (standalone version)
print_info "安装 Docker Compose..."
if [[ "$REGION" == "CN" ]]; then
    # Try to get version from GitHub mirror
    DOCKER_COMPOSE_VERSION=$(curl -s --max-time 10 "${GITHUB_MIRROR}/docker/compose/releases/latest" | grep "tag_name" | cut -d '"' -f 4 | sed 's/v//' || echo "")
    
    if [[ -z "$DOCKER_COMPOSE_VERSION" ]]; then
        # Fallback: try direct GitHub
        DOCKER_COMPOSE_VERSION=$(curl -s --max-time 10 "https://api.github.com/repos/docker/compose/releases/latest" | grep "tag_name" | cut -d '"' -f 4 | sed 's/v//' || echo "")
    fi
    
    if [[ -n "$DOCKER_COMPOSE_VERSION" ]]; then
        COMPOSE_URL="${DOCKER_COMPOSE_MIRROR}/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
        print_info "使用国内镜像下载 Docker Compose v${DOCKER_COMPOSE_VERSION}..."
        sudo curl -L --max-time 300 --connect-timeout 30 "${COMPOSE_URL}" -o /usr/local/bin/docker-compose || {
            print_warn "从镜像源下载失败，尝试使用 GitHub 直连..."
            sudo curl -L --max-time 300 --connect-timeout 30 "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || {
                print_error "下载 Docker Compose 失败"
                exit 1
            }
        }
    else
        print_error "无法获取 Docker Compose 版本信息"
        exit 1
    fi
else
    DOCKER_COMPOSE_VERSION=$(curl -s --max-time 10 "https://api.github.com/repos/docker/compose/releases/latest" | grep "tag_name" | cut -d '"' -f 4 | sed 's/v//' || echo "")
    if [[ -n "$DOCKER_COMPOSE_VERSION" ]]; then
        sudo curl -L --max-time 300 "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || {
            print_error "下载 Docker Compose 失败"
            exit 1
        }
    else
        print_error "无法获取 Docker Compose 版本信息"
        exit 1
    fi
fi

# Apply executable permissions to the Docker Compose binary
sudo chmod +x /usr/local/bin/docker-compose || {
    print_error "无法设置 Docker Compose 执行权限"
    exit 1
}

# Verify installation
print_info "验证安装..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    print_info "Docker 版本: $DOCKER_VERSION"
else
    print_error "Docker 未正确安装"
    exit 1
fi

if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version)
    print_info "Docker Compose 版本: $COMPOSE_VERSION"
else
    print_warn "Docker Compose 未正确安装（但 Docker Compose 插件可能已安装）"
fi

# Test Docker
print_info "测试 Docker 运行..."
if sudo docker run --rm hello-world &> /dev/null; then
    print_info "Docker 测试成功！"
else
    print_warn "Docker 测试失败，但安装可能已完成"
fi

echo ""
print_info "=========================================="
print_info "Docker 和 Docker Compose 安装完成！"
print_info "=========================================="
print_warn "注意：如果当前用户已添加到 docker 组，请注销并重新登录以使权限生效"
print_warn "或者运行: newgrp docker"
echo ""

## curl -fsSL https://raw.githubusercontent.com/IEatLemons/Quick-Installation/main/ins-docker.sh | bash