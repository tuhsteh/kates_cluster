ls /boot/extlinux/extlinux.conf 2>&1
cat /proc/cmdline
mount | grep overlay
swapon --show
which update-initramfs 2>&1
systemctl status zramswap 2>&1 | head -3
