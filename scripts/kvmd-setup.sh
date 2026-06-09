#!/bin/bash
# PiKVM boot setup script
# 在 kvmd 服务启动前执行，确保设备和权限正确

# Wait for devices to be ready
sleep 3

# Create kvmd-video symlink
ln -sf /dev/video0 /dev/kvmd-video

# Set EDID (use built-in hdmi type)
v4l2-ctl --device=/dev/kvmd-video --set-edid=type=hdmi 2>/dev/null

# Set DV timings
v4l2-ctl --device=/dev/kvmd-video --set-dv-bt-timings query 2>/dev/null

# Fix permissions
mkdir -p /run/kvmd
chown -R kvmd:kvmd /run/kvmd
chmod 775 /run/kvmd

# Add kvmd user to dialout group
usermod -aG dialout kvmd 2>/dev/null

exit 0
