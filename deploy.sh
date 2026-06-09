#!/bin/bash
# ============================================================================
# fruity-pikvm-deploy: 一键部署 PiKVM 到 Raspberry Pi 4 + TC358743
# ============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# 检查环境
# ============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 运行此脚本"
        exit 1
    fi
}

check_arch() {
    ARCH=$(uname -m)
    if [ "$ARCH" != "aarch64" ]; then
        log_error "仅支持 aarch64 架构，当前: $ARCH"
        exit 1
    fi
}

check_rpi() {
    if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        log_warn "未检测到 Raspberry Pi，可能不兼容"
    fi
}

# ============================================================================
# 步骤 1：更新系统
# ============================================================================
update_system() {
    log_info "更新系统包..."
    apt update
    apt upgrade -y
}

# ============================================================================
# 步骤 2：安装依赖
# ============================================================================
install_deps() {
    log_info "安装依赖..."
    apt install -y \
        git wget curl build-essential cmake \
        libsystemd-dev python3-dev python3-pip python3-setuptools \
        libjpeg62-turbo libgpiod-dev \
        nginx iptables \
        tesseract-ocr tesseract-ocr-eng \
        v4l-utils
}

# ============================================================================
# 步骤 3：编译安装 Python 3.10
# ============================================================================
install_python310() {
    if command -v python3.10 &>/dev/null; then
        log_info "Python 3.10 已安装，跳过"
        return
    fi

    log_info "编译安装 Python 3.10（约 20-40 分钟）..."

    # 使用磁盘而非 /tmp（tmpfs 空间不足）
    BUILD_DIR="/root/python-build"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    wget -q https://www.python.org/ftp/python/3.10.9/Python-3.10.9.tgz
    tar xzf Python-3.10.9.tgz
    cd Python-3.10.9

    ./configure --prefix=/usr/local
    make -j$(nproc)
    make install

    # 创建 kvmd.pth 让 Python 3.10 找到 kvmd-packages
    mkdir -p /usr/local/lib/python3.10/site-packages
    echo "/usr/local/lib/python3.10/kvmd-packages" > /usr/local/lib/python3.10/site-packages/kvmd.pth

    # 设置 /usr/sbin/python 指向 python3.10
    ln -sf /usr/local/bin/python3.10 /usr/sbin/python

    # 清理
    cd /
    rm -rf "$BUILD_DIR"

    log_info "Python 3.10 安装完成"
}

# ============================================================================
# 步骤 4：安装 fruity-pikvm
# ============================================================================
install_fruity_pikvm() {
    log_info "安装 fruity-pikvm..."

    cd /tmp
    if [ ! -d "fruity-pikvm" ]; then
        git clone https://github.com/jacobbar/fruity-pikvm.git
    fi
    cd fruity-pikvm

    # 运行安装脚本（会编译 Python 并安装 deb 包）
    ./install.sh || true

    log_info "fruity-pikvm 安装完成"
}

# ============================================================================
# 步骤 5：修复兼容性问题
# ============================================================================
fix_compat() {
    log_info "修复兼容性问题..."

    # 5.1 安装 Python 3.10 的 systemd 模块
    log_info "编译 systemd-python for Python 3.10..."
    cd /tmp
    wget -q https://files.pythonhosted.org/packages/source/s/systemd-python/systemd-python-235.tar.gz
    tar xzf systemd-python-235.tar.gz
    cd systemd-python-235
    /usr/local/bin/python3.10 setup.py build_ext --inplace 2>/dev/null || true
    cp -r build/lib.*/systemd /usr/local/lib/python3.10/kvmd-packages/ 2>/dev/null || \
    cp -r systemd/*.py /usr/local/lib/python3.10/kvmd-packages/systemd/ 2>/dev/null || true
    cd /
    rm -rf /tmp/systemd-python-235*

    # 5.2 安装 Pillow
    log_info "安装 Pillow..."
    /usr/local/bin/python3.10 -m pip install Pillow --target=/usr/local/lib/python3.10/site-packages --quiet 2>/dev/null || true

    # 5.3 安装 zstandard
    log_info "安装 zstandard..."
    /usr/local/bin/python3.10 -m pip install zstandard --target=/usr/local/lib/python3.10/site-packages --quiet 2>/dev/null || true

    # 5.4 编译安装 libjpeg-turbo（带 JPEG8 ABI）
    log_info "编译 libjpeg-turbo with JPEG8 ABI..."
    if [ ! -f /usr/lib/aarch64-linux-gnu/libjpeg.so.8 ]; then
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

    # 5.5 编译安装 libgpiod 1.6.x
    log_info "编译 libgpiod 1.6.x..."
    if [ ! -f /usr/lib/aarch64-linux-gnu/libgpiod.so.2 ]; then
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

    # 5.6 创建 gpiod 兼容层（1.x API -> 2.x）
    log_info "创建 gpiod 兼容层..."
    create_gpiod_wrapper

    # 5.7 删除 kvmd-packages 中与系统冲突的模块
    log_info "清理冲突模块..."
    rm -rf /usr/local/lib/python3.10/kvmd-packages/systemd* 2>/dev/null
    rm -rf /usr/local/lib/python3.10/kvmd-packages/PIL /usr/local/lib/python3.10/kvmd-packages/Pillow* 2>/dev/null

    # 5.8 重建 systemd 模块（使用正确的 .so 文件）
    if [ -d /tmp/systemd-python-235 ]; then
        cp -r /tmp/systemd-python-235/build/lib.*/systemd /usr/local/lib/python3.10/kvmd-packages/ 2>/dev/null || true
    fi

    ldconfig
    log_info "兼容性修复完成"
}

# 创建 gpiod 兼容层
create_gpiod_wrapper() {
    local GPIOD_DIR="/usr/local/lib/python3.10/kvmd-packages/gpiod"

    # 备份原始 gpiod 2.x 模块
    if [ -f "$GPIOD_DIR/__init__.py" ] && [ ! -f "$GPIOD_DIR/_gpiod2.py" ]; then
        cp "$GPIOD_DIR/__init__.py" "$GPIOD_DIR/_gpiod2.py"
    fi

    cat > "$GPIOD_DIR/__init__.py" << 'GPIOD_WRAPPER'
# gpiod 1.x -> 2.x compatibility wrapper for kvmd
import os as _os
import glob as _glob
from . import _gpiod2 as _g2

# Constants from gpiod 1.x
LINE_REQ_DIR_IN = 1
LINE_REQ_DIR_OUT = 2
LINE_REQ_EV_RISING_EDGE = 4
LINE_REQ_EV_FALLING_EDGE = 8
LINE_REQ_EV_BOTH_EDGES = 12

class LineEvent:
    RISING_EDGE = 1
    FALLING_EDGE = 2
    def __init__(self, event_type, offset, timestamp):
        self.type = event_type
        self.offset = offset
        self.timestamp = timestamp

class Line:
    def __init__(self, chip, offset, request=None):
        self._chip = chip
        self._offset = offset
        self._request = request
        self._direction = None

    def request(self, consumer, flags=0, default_vals=None, **kwargs):
        self._direction = flags
        settings = _g2.LineSettings()
        if flags == LINE_REQ_DIR_OUT:
            settings.direction = _g2.line.Direction.OUTPUT
            if default_vals:
                settings.output_values = default_vals
        elif flags & LINE_REQ_EV_BOTH_EDGES:
            settings.direction = _g2.line.Direction.INPUT
            settings.edge_detection = _g2.line.Edge.BOTH
            settings.bias = _g2.line.Bias.DISABLED
        else:
            settings.direction = _g2.line.Direction.INPUT
        try:
            config = {self._offset: settings}
            self._request = self._chip._real.request_lines(consumer=consumer, config=config)
        except Exception:
            pass

    def get_value(self):
        if self._request:
            try:
                vals = self._request.get_values([self._offset])
                return vals[0] if vals else 0
            except Exception:
                return 0
        return 0

    def set_value(self, val):
        if self._request:
            try:
                self._request.set_values({self._offset: val})
            except Exception:
                pass

    def release(self):
        if self._request:
            try:
                self._request.release()
            except Exception:
                pass
            self._request = None

    def __del__(self):
        self.release()

class LineBulk:
    def __init__(self, lines=None):
        self._lines = lines or []
        self._request = None

    def request(self, consumer, flags=0, default_vals=None, **kwargs):
        settings = _g2.LineSettings()
        if flags == LINE_REQ_DIR_OUT:
            settings.direction = _g2.line.Direction.OUTPUT
            if default_vals:
                settings.output_values = default_vals
        elif flags & LINE_REQ_EV_BOTH_EDGES:
            settings.direction = _g2.line.Direction.INPUT
            settings.edge_detection = _g2.line.Edge.BOTH
            settings.bias = _g2.line.Bias.DISABLED
        else:
            settings.direction = _g2.line.Direction.INPUT
        offsets = [l._offset for l in self._lines]
        config = {off: settings for off in offsets}
        chip = self._lines[0]._chip if self._lines else None
        if chip:
            try:
                self._request = chip._real.request_lines(consumer=consumer, config=config)
                for line in self._lines:
                    line._request = self._request
            except Exception:
                pass

    def get_values(self):
        if self._request:
            offsets = [l._offset for l in self._lines]
            try:
                return self._request.get_values(offsets)
            except Exception:
                return [0] * len(self._lines)
        return [0] * len(self._lines)

    def set_values(self, vals):
        if self._request:
            offsets = [l._offset for l in self._lines]
            try:
                self._request.set_values(dict(zip(offsets, vals)))
            except Exception:
                pass

    def __iter__(self):
        return iter(self._lines)

    def __len__(self):
        return len(self._lines)

    def __getitem__(self, idx):
        return self._lines[idx]

class Chip:
    def __init__(self, path):
        self._path = path
        self._real = None
        try:
            self._real = _g2.Chip(path)
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def close(self):
        if self._real:
            try:
                self._real.close()
            except Exception:
                pass
            self._real = None

    def get_lines(self, offsets):
        lines = [Line(self, off) for off in offsets]
        return LineBulk(lines)

    def get_line(self, offset):
        return Line(self, offset)

    def event_wait(self, sec=0, nsec=0):
        if self._real:
            try:
                timeout_ns = int(sec * 1e9 + nsec)
                events = self._real.wait_edge_events(timeout=timeout_ns / 1e9)
                result = []
                for ev in events:
                    ev_type = LineEvent.RISING_EDGE if ev.event_type == _g2.EdgeEvent.Type.RISING else LineEvent.FALLING_EDGE
                    result.append(LineEvent(ev_type, ev.line_offset(), ev.timestamp_ns()))
                return result
            except Exception:
                return []
        return []

    def event_read(self):
        return []

class chip_iter:
    def __init__(self):
        self._chips = sorted(_glob.glob('/dev/gpiochip*'))
        self._idx = 0

    def __iter__(self):
        return self

    def __next__(self):
        while self._idx < len(self._chips):
            path = self._chips[self._idx]
            self._idx += 1
            try:
                chip = Chip(path)
                if chip._real:
                    return chip
            except Exception:
                continue
        raise StopIteration

class line_iter:
    def __init__(self, chip):
        self._chip = chip
        self._lines = []
        self._idx = 0
        if chip._real:
            try:
                info = chip._real.info()
                for i in range(info.num_lines):
                    self._lines.append(Line(chip, i))
            except Exception:
                pass

    def __iter__(self):
        return self

    def __next__(self):
        if self._idx >= len(self._lines):
            raise StopIteration
        line = self._lines[self._idx]
        self._idx += 1
        return line

Line = Line
Chip = Chip
ChipIter = chip_iter
LineEvent = LineEvent
LineRequest = LineBulk
LineBulk = LineBulk

def find_line(name):
    for path in sorted(_glob.glob('/dev/gpiochip*')):
        try:
            chip = Chip(path)
            if chip._real:
                info = chip._real.info()
                for i in range(info.num_lines):
                    line_info = chip._real.line_info(i)
                    if line_info.name == name:
                        return Line(chip, i)
                chip.close()
        except Exception:
            continue
    return None

def make_chip_iter():
    return chip_iter()
GPIOD_WRAPPER
}

# ============================================================================
# 步骤 6：应用配置
# ============================================================================
apply_config() {
    log_info "应用配置..."

    # 复制配置文件
    cp "$SCRIPT_DIR/configs/override.yaml" /etc/kvmd/override.yaml

    # 复制启动脚本
    cp "$SCRIPT_DIR/scripts/kvmd-setup.sh" /usr/local/bin/kvmd-setup.sh
    chmod +x /usr/local/bin/kvmd-setup.sh

    # 复制 systemd 服务
    cp "$SCRIPT_DIR/systemd/kvmd-setup.service" /etc/systemd/system/
    systemctl daemon-reload

    # 启用服务
    systemctl enable kvmd-setup kvmd kvmd-nginx kvmd-webterm

    # 复制 EDID
    cp "$SCRIPT_DIR/edid/v2-hdmi.hex" /etc/kvmd/tc358743-edid.hex 2>/dev/null || true

    # 修复权限
    mkdir -p /run/kvmd
    chown -R kvmd:kvmd /run/kvmd
    chmod 775 /run/kvmd
    usermod -aG dialout kvmd 2>/dev/null || true

    log_info "配置应用完成"
}

# ============================================================================
# 步骤 7：配置 OTG
# ============================================================================
configure_otg() {
    log_info "配置 OTG..."

    local CONFIG_FILE="/boot/firmware/config.txt"

    # 检查是否已有 dwc2 配置
    if ! grep -q "dtoverlay=dwc2" "$CONFIG_FILE"; then
        cat >> "$CONFIG_FILE" << EOF

# PiKVM OTG configuration
dtoverlay=dwc2,dr_mode=otg
EOF
    fi

    # 禁用 otg_mode=1（与 dwc2 冲突）
    sed -i 's/^otg_mode=1/#otg_mode=1  # Disabled for PiKVM OTG/' "$CONFIG_FILE"

    log_info "OTG 配置完成"
}

# ============================================================================
# 步骤 8：启动服务
# ============================================================================
start_services() {
    log_info "启动服务..."

    # 创建符号链接
    ln -sf /dev/video0 /dev/kvmd-video

    # 设置 EDID
    v4l2-ctl --device=/dev/kvmd-video --set-edid=type=hdmi 2>/dev/null || true
    v4l2-ctl --device=/dev/kvmd-video --set-dv-bt-timings query 2>/dev/null || true

    # 启动服务
    systemctl restart kvmd-setup 2>/dev/null || true
    systemctl restart kvmd kvmd-nginx kvmd-webterm 2>/dev/null || true

    log_info "服务启动完成"
}

# ============================================================================
# 主流程
# ============================================================================
main() {
    echo "============================================"
    echo "  fruity-pikvm-deploy: PiKVM 一键部署"
    echo "  Raspberry Pi 4 + TC358743"
    echo "============================================"
    echo ""

    check_root
    check_arch
    check_rpi

    log_info "开始部署..."
    echo ""

    update_system
    install_deps
    install_python310
    install_fruity_pikvm
    fix_compat
    apply_config
    configure_otg
    start_services

    echo ""
    echo "============================================"
    log_info "部署完成！"
    echo ""
    echo "  访问地址: https://$(hostname -I | awk '{print $1}')"
    echo "  默认用户: admin / admin"
    echo ""
    echo "  请重启以使 OTG 配置生效: sudo reboot"
    echo "============================================"
}

main "$@"
