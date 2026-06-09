## 1.0.0

### 新增
- 一键部署脚本 `deploy.sh`，支持自动化安装和配置
- 完整的 README 部署文档，包含硬件要求、连接方式、已知问题解决方案
- kvmd 启动脚本 `kvmd-setup.sh`，自动设置 EDID、DV timings、权限
- systemd 服务 `kvmd-setup.service`，开机自启动
- gpiod 1.x → 2.x 兼容层，解决内核 6.12 上的 API 不兼容问题
- libjpeg-turbo with JPEG8 ABI 编译支持
- libgpiod 1.6.x 编译支持
- systemd-python for Python 3.10 编译支持
- 双鼠标模式配置（Absolute + Relative）
- TC358743 HDMI 采集卡 EDID 配置
- USB OTG dwc2 设备模式配置

### 修复
- Python 3.10 与 Debian Trixie (Python 3.13) 的模块兼容性问题
- `/tmp` tmpfs 空间不足导致编译失败的问题
- libjpeg.so.8 缺失导致 ustreamer 无法启动的问题
- libgpiod.so.2 缺失导致 ustreamer 无法启动的问题
- gpiod C 扩展与内核 6.12 ioctl 不兼容的问题
- systemd._journal 模块缺失导致 kvmd 无法启动的问题
- PIL/Pillow 模块冲突问题
- zstandard 模块缺失问题
- dwc_otg 旧驱动与 dwc2 overlay 冲突问题
- `/dev/kvmd-video` 符号链接重启后丢失的问题

