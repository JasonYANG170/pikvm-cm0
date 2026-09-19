# CM0 视频优化记录

适用环境：Debian 13 arm64、KVMD 3.198、uStreamer 5.37、Janus 1.1.2、TC358743。
保留桌面，不修改 SSH/Web 账号、密码、证书或 Wi-Fi 连接信息。

## 已有安装应用优化

在完整仓库目录运行，不要重新执行初次安装用的 `deploy.sh`：

```bash
# 可选：补齐 WebRTC（需要已安装 gcc、make、Janus 和对应运行库）
sudo bash scripts/install-webrtc.sh
# 加载视频参数、EDID，并关闭 wlan0 省电
sudo bash scripts/apply-optimizations.sh
```

脚本会显示 `/var/backups/` 下的备份和回滚命令。回退全部变化时，先回退视频配置，再回退 WebRTC 安装。
重启 KVMD 会使登录会话失效，请使用原来的网页账号重新登录。
不安装 WebRTC 时仍可使用 MJPEG；配置 H.264 sink 本身不会开启网页 WebRTC。

## 变更与验证范围

- `--dv-timings` 自动跟随 HDMI 时序，不再只在开机时查询一次。
- 使用官方 `_1080p-by-default.hex` EDID，首选 1920×1080 约 50Hz，两个块校验和已验证。
- `desired_fps.default: 0` 为自动帧率；单个 M2M-VIDEO 编码器、3 个采集缓冲区。
- 保留重复帧过滤：静止画面显示 1–2 fps 正常，不等于采集只有 1–2 fps。
- H.264 默认 5000 kbps、GOP 30；保留 MJPEG 并接通 JPEG 质量调节。
- Janus 使用现有 Nginx 认证后的 Unix WebSocket，不另开未认证的 HTTP 服务。
- Wi-Fi 省电关闭，通过 NetworkManager 配置持久化。

在当前 1024×768@60Hz 信号下，本机连续 MJPEG 输出及采集约 60 fps，H.264 已实际消费 60 帧。
Janus 插件协议握手成功，未登录访问 `/janus/ws` 返回 401。
这些结果不代表浏览器在动态画面、Wi-Fi 或 1080p 下的帧率；WebRTC 浏览器端仍需登录后验收。

HDMI 输入由被控电脑决定：在被控电脑显示设置中选择 1920×1080、50Hz；必要时重插 HDMI 重新读取 EDID。
网页选择分辨率不会强制改变源电脑输出。此 CSI 方案不以 1080p60 为支持目标。

## 验证

```bash
systemctl is-active kvmd kvmd-nginx kvmd-janus-static
v4l2-ctl -d /dev/video0 --query-dv-timings
sudo curl --unix-socket /run/kvmd/ustreamer.sock http://localhost/state
iw dev wlan0 get power_save
```

打开视频页面时才会启动 uStreamer；没有客户端时 socket 不存在是正常的。
WebRTC 页面应显示 H.264；切换 MJPEG 应仍能播放。还应测试源电脑晚开机、HDMI 重插和分辨率切换。

## 上游来源

- [PiKVM EDID](https://github.com/pikvm/kvmd/blob/master/configs/kvmd/edid/_1080p-by-default.hex)（GPL-3.0；本仓库保存已验证字节）
- [uStreamer v5.37](https://github.com/pikvm/ustreamer/tree/v5.37)（GPL-3.0）
- [Janus v1.1.2](https://github.com/meetecho/janus-gateway/tree/v1.1.2)（GPL-3.0）
- [webrtc-adapter 8.2.3](https://www.npmjs.com/package/webrtc-adapter/v/8.2.3)（BSD-3-Clause）

WebRTC 构建脚本固定源码版本和 SHA-256，仅将 Debian 开发包解压到独立构建目录，不升级系统运行库。
构建目录保留用于审计。`--build-only` 可只编译而不安装。
