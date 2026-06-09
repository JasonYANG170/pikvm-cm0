#!/bin/bash
# fix-compat.sh: 修复 fruity-pikvm 在 Debian Trixie 上的兼容性问题
# 单独运行此脚本来修复已安装的 fruity-pikvm

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "请使用 sudo 运行"
    exit 1
fi

log_info "开始修复兼容性问题..."

# 1. 确保 Python 3.10 已安装
if ! command -v python3.10 &>/dev/null; then
    log_error "Python 3.10 未安装，请先运行 deploy.sh"
    exit 1
fi

# 2. 创建 kvmd.pth
log_info "创建 kvmd.pth..."
mkdir -p /usr/local/lib/python3.10/site-packages
echo "/usr/local/lib/python3.10/kvmd-packages" > /usr/local/lib/python3.10/site-packages/kvmd.pth

# 3. 设置 /usr/sbin/python
log_info "设置 /usr/sbin/python..."
ln -sf /usr/local/bin/python3.10 /usr/sbin/python

# 4. 安装 Python 依赖
log_info "安装 Python 依赖..."
/usr/local/bin/python3.10 -m pip install Pillow --target=/usr/local/lib/python3.10/site-packages --quiet 2>/dev/null || true
/usr/local/bin/python3.10 -m pip install zstandard --target=/usr/local/lib/python3.10/site-packages --quiet 2>/dev/null || true

# 5. 编译 systemd-python
log_info "编译 systemd-python..."
if ! /usr/local/bin/python3.10 -c "import systemd.journal" 2>/dev/null; then
    cd /tmp
    wget -q https://files.pythonhosted.org/packages/source/s/systemd-python/systemd-python-235.tar.gz 2>/dev/null || true
    if [ -f systemd-python-235.tar.gz ]; then
        tar xzf systemd-python-235.tar.gz
        cd systemd-python-235
        /usr/local/bin/python3.10 setup.py build_ext --inplace 2>/dev/null || true
        mkdir -p /usr/local/lib/python3.10/kvmd-packages/systemd
        cp -r build/lib.*/systemd/* /usr/local/lib/python3.10/kvmd-packages/systemd/ 2>/dev/null || \
        cp systemd/*.py /usr/local/lib/python3.10/kvmd-packages/systemd/ 2>/dev/null || true
        cp systemd/*.so /usr/local/lib/python3.10/kvmd-packages/systemd/ 2>/dev/null || true
        cd /
        rm -rf /tmp/systemd-python-235*
    fi
fi

# 6. 编译 libjpeg-turbo with JPEG8 ABI
log_info "检查 libjpeg.so.8..."
if [ ! -f /usr/lib/aarch64-linux-gnu/libjpeg.so.8 ]; then
    log_info "编译 libjpeg-turbo with JPEG8 ABI..."
    cd /tmp
    wget -q https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/2.1.5.tar.gz -O libjpeg-turbo-2.1.5.tar.gz
    tar xzf libjpeg-turbo-2.1.5.tar.gz
    cd libjpeg-turbo-2.1.5
    mkdir build && cd build
    cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=/usr/lib/aarch64-linux-gnu -DWITH_JPEG8=1 .. >/dev/null 2>&1
    make -j$(nproc) >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /
    rm -rf /tmp/libjpeg-turbo-2.1.5*
fi

# 7. 编译 libgpiod 1.6.x
log_info "检查 libgpiod.so.2..."
if [ ! -f /usr/lib/aarch64-linux-gnu/libgpiod.so.2 ]; then
    log_info "编译 libgpiod 1.6.x..."
    cd /tmp
    wget -q https://mirrors.edge.kernel.org/pub/software/libs/libgpiod/libgpiod-1.6.4.tar.xz
    tar xf libgpiod-1.6.4.tar.xz
    cd libgpiod-1.6.4
    ./configure --prefix=/usr --libdir=/usr/lib/aarch64-linux-gnu --enable-tools=no --enable-tests=no --disable-bindings >/dev/null 2>&1
    make -j$(nproc) >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /
    rm -rf /tmp/libgpiod-1.6.4*
fi

# 8. 清理冲突模块
log_info "清理冲突模块..."
rm -rf /usr/local/lib/python3.10/kvmd-packages/PIL /usr/local/lib/python3.10/kvmd-packages/Pillow* 2>/dev/null || true

# 9. 重建 systemd 模块
log_info "重建 systemd 模块..."
if [ -d /tmp/systemd-python-235 ]; then
    cp -r /tmp/systemd-python-235/build/lib.*/systemd /usr/local/lib/python3.10/kvmd-packages/ 2>/dev/null || true
fi

# 10. 更新 ldconfig
ldconfig

# 11. 验证
log_info "验证修复..."
/usr/local/bin/python3.10 -c "import systemd.journal; print('systemd.journal OK')" 2>/dev/null || log_warn "systemd.journal 未就绪"
/usr/local/bin/python3.10 -c "from PIL import Image; print('PIL OK')" 2>/dev/null || log_warn "PIL 未就绪"
/usr/local/bin/python3.10 -c "import zstandard; print('zstandard OK')" 2>/dev/null || log_warn "zstandard 未就绪"

log_info "兼容性修复完成！"
log_info "请运行: sudo systemctl restart kvmd"
