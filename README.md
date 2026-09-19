# PIKVM-CM0

一键部署 PiKVM 到 Raspberry Pi CM0 + TC358743 HDMI 采集卡

## 已有设备的视频优化

已有安装请先阅读 [优化与回滚说明](docs/optimizations.md)，无需重装系统：

```bash
git clone https://github.com/JasonYANG170/pikvm-cm0.git
cd pikvm-cm0
sudo bash scripts/install-webrtc.sh       # 可选，适配 Janus 1.1.2 / uStreamer 5.37
sudo bash scripts/apply-optimizations.sh
```

包含自动 HDMI 时序、1080p50 EDID、硬件编码、自动帧率、Wi-Fi 省电关闭和 H.264/WebRTC。
保留桌面和账号；重启视频服务后需重新登录。已测 1024×768 下本机约 60 fps，不代表 1080p 或浏览器实际帧率。

## 硬件要求

| 组件 | 型号 |
|------|------|
| 单板计算机 | Raspberry Pi CM0 |
| HDMI 采集 | TC358743 HDMI-to-CSI  |
| USB OTG | USB-C OTG 线|
| 存储 | 16GB |
| 电源 | USB-C 5V/3A 电源 |


## 快速部署

### 1. 准备系统镜像

1. 下载 [Raspberry Pi OS Lite (64-bit)](https://www.raspberrypi.com/software/operating-systems/)
2. 使用 [Raspberry Pi Imager](https://www.raspberrypi.com/software/) 烧录到 SD 卡
3. 在 Imager 中预配置：
   - 启用 SSH
   - 设置用户名密码（如 `rbpi-kvm` / `rbpi-kvm`）
   - 配置 WiFi（可选）

### 2. 首次启动

1. 插入 SD 卡，连接 HDMI 采集卡和 OTG 线
2. 开机，等待系统启动
3. SSH 连接到树莓派：
   ```bash
   ssh rbpi-kvm@<树莓派IP>
   ```

### 3. 一键部署

```bash
# 下载完整仓库（部署脚本依赖 configs、scripts、systemd 和 edid）
git clone https://github.com/JasonYANG170/pikvm-cm0.git
cd pikvm-cm0
chmod +x deploy.sh

# 运行部署（约 30-60 分钟）
sudo ./deploy.sh
```

### 4. 访问 PiKVM

部署完成后，浏览器打开：
```
https://<树莓派IP>
```

默认登录：
- 用户名：`admin`
- 密码：`admin`

## 手动部署

如果自动脚本不适用，可以手动执行以下步骤：

### 步骤 1：更新系统

```bash
sudo apt update && sudo apt upgrade -y
```

### 步骤 2：安装依赖

```bash
sudo apt install -y git wget build-essential cmake \
  libsystemd-dev libjpeg62-turbo libgpiod-dev \
  nginx iptables tesseract-ocr tesseract-ocr-eng \
  python3-dev python3-pip python3-setuptools
```

### 步骤 3：编译安装 Python 3.10

```bash
cd /tmp
wget https://www.python.org/ftp/python/3.10.9/Python-3.10.9.tgz
tar xzf Python-3.10.9.tgz
cd Python-3.10.9
./configure --prefix=/usr/local
make -j$(nproc)
sudo make install
```

### 步骤 4：安装 fruity-pikvm

```bash
cd /tmp
git clone https://github.com/jacobbar/fruity-pikvm.git
cd fruity-pikvm
sudo ./install.sh
```

### 步骤 5：修复兼容性问题

```bash
# 运行修复脚本
sudo ./scripts/fix-compat.sh
```

### 步骤 6：应用配置

```bash
sudo cp configs/override.yaml /etc/kvmd/override.yaml
sudo cp edid/tc358743-edid.hex /etc/kvmd/tc358743-edid.hex
sudo cp scripts/kvmd-setup.sh /usr/local/bin/kvmd-setup.sh
sudo chmod +x /usr/local/bin/kvmd-setup.sh
sudo cp systemd/kvmd-setup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kvmd-setup kvmd kvmd-nginx kvmd-webterm
```

### 步骤 7：配置 OTG

```bash
# 编辑 /boot/firmware/config.txt，确保有以下内容：
# [all]
# dtoverlay=dwc2,dr_mode=otg
# dtoverlay=tc358743

sudo reboot
```

## 配置说明

### override.yaml

```yaml
kvmd:
    msd:
        type: disabled           # MSD 功能（需要额外分区）
    gpio:
        drivers: {}              # GPIO 驱动
        scheme: {}               # GPIO 方案
    hid:
        mouse_alt:
            device: /dev/kvmd-hid-mouse-alt  # 启用双鼠标模式
    streamer:
        resolution:
            default: 1920x1080       # 实际采集自动跟随 HDMI 源
        desired_fps:
            default: 0               # 自动帧率
        cmd:
            - "/usr/bin/ustreamer"
            - "--device=/dev/kvmd-video"
            - "--format=uyvy"    # TC358743 输出格式
            - "--dv-timings"
            - "--encoder=M2M-VIDEO"
            # ... 其他参数
```

### kvmd-setup.sh

启动时自动执行：
- 创建 `/dev/kvmd-video` 符号链接
- 设置 EDID
- 由 uStreamer 持续跟随 DV timings，支持源设备晚开机
- 修复权限

### boot/config.txt

```ini
[all]
dtoverlay=dwc2,dr_mode=otg    # USB OTG 设备模式
dtoverlay=tc358743             # TC358743 HDMI 采集驱动
enable_uart=1                  # 启用串口
```

## 已知问题与解决方案

### 1. 黑屏 / NO SIGNAL

**原因**：EDID 未设置或 HDMI 源设备未输出信号

**解决**：
```bash
sudo systemctl stop kvmd
sudo /usr/local/bin/kvmd-setup.sh
sudo systemctl restart kvmd
```

### 2. 分辨率显示 640x480

**原因**：DV timings 未正确设置

**解决**：
```bash
v4l2-ctl --device /dev/video0 --query-dv-timings
# 使用 scripts/apply-optimizations.sh 启用 --dv-timings 自动同步。
```

### 3. 鼠标键盘无响应

**原因**：USB OTG 连接问题

**检查**：
```bash
# 在被控设备上运行 lsusb，应看到 PiKVM 设备
lsusb | grep -i pikvm

# 检查 HID 设备
ls -la /dev/hidg*

# 测试写入
sudo sh -c 'echo -ne "\x00\x00\x04\x00\x00\x00\x00\x00" > /dev/hidg0'
```

**解决**：
- 确认使用 OTG 线（不是充电线）
- 确认连接到树莓派的 USB-C 口
- 尝试被控设备的其他 USB 口

### 4. 切换鼠标模式

在 Web 界面点击 **System** 菜单，切换：
- **Absolute**：绝对定位（默认，适合桌面系统）
- **Relative**：相对定位（适合 BIOS/UEFI）

### 5. libjpeg.so.8 缺失

```bash
# 从源码编译 libjpeg-turbo（带 JPEG8 ABI）
cd /tmp
wget https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/2.1.5.tar.gz
tar xzf 2.1.5.tar.gz
cd libjpeg-turbo-2.1.5
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr -DWITH_JPEG8=1 ..
make -j$(nproc)
sudo make install
sudo ldconfig
```

### 6. libgpiod.so.2 缺失

```bash
# 从源码编译 libgpiod 1.6.x
cd /tmp
wget https://mirrors.edge.kernel.org/pub/software/libs/libgpiod/libgpiod-1.6.4.tar.xz
tar xf libgpiod-1.6.4.tar.xz
cd libgpiod-1.6.4
./configure --prefix=/usr --enable-tools=no --enable-tests=no --disable-bindings
make -j$(nproc)
sudo make install
sudo ldconfig
```

## 文件结构

```
fruity-pikvm-deploy/
├── README.md              # 本文档
├── deploy.sh              # 一键部署脚本
├── configs/
│   ├── override.yaml      # kvmd 配置
│   └── boot-config.txt    # 树莓派启动配置
├── scripts/
│   ├── kvmd-setup.sh      # 启动脚本
│   └── fix-compat.sh      # 兼容性修复脚本
├── systemd/
│   └── kvmd-setup.service # systemd 服务
└── edid/
    ├── v2-hdmi.hex        # PiKVM V2 EDID
    └── tc358743-edid.hex  # TC358743 EDID
```

## 许可证

本项目基于 fruity-pikvm 和 PiKVM 开源项目。

- [fruity-pikvm](https://github.com/jacobbar/fruity-pikvm) - GPLv3
- [PiKVM](https://github.com/pikvm/pikvm) - GPLv3
- [ustreamer](https://github.com/pikvm/ustreamer) - GPLv3

