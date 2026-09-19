## 1.1.1

- 为 KVMD 3.198 增加可回滚的网页触控补丁，不升级后端。
- 支持轻点单击、双指滚动、浮动鼠标按键和拖拽；取消手势与失焦时释放拖拽。
- 增加输入手势和按键释放回归测试。
- 适配 Janus 1.x 的 onremotetrack 回调，修复 WebRTC 已连接但画面未显示；修复页面关闭事件重复调用。

## 1.1.0

- 同步设备已验证的视频配置：动态 DV timings、自动帧率、单 M2M 硬件编码器和 3 个缓冲区。
- 持久加载官方 1080p50 EDID，修正部署时覆盖为通用 1080p60 EDID 的问题。
- 增加带备份和回滚的视频优化脚本，保留账号及其他 KVMD 设置。
- 增加固定版本及源码校验和的 Janus/uStreamer WebRTC 插件构建脚本、前端资源安装和配置。
- 启用 H.264 5 Mbps，并保留可调 JPEG 质量的 MJPEG 回退。
- NetworkManager 关闭 Wi-Fi 省电，保留桌面。
- 记录验证边界：1024×768 本机约 60 fps；不宣称 1080p60 或已完成浏览器端 WebRTC 验收。

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
