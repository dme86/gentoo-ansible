#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DISK=${1:-"$PROJECT_DIR/.qemu/gentoo.qcow2"}
SSH_PORT=${SSH_PORT:-2222}
VM_CLIPBOARD=${VM_CLIPBOARD:-1}

case "$VM_CLIPBOARD" in
  0|1) ;;
  *) printf 'VM_CLIPBOARD must be 0 or 1.\n' >&2; exit 1 ;;
esac

if [ ! -f "$DISK" ]; then
  printf 'QEMU disk not found: %s\n' "$DISK" >&2
  exit 1
fi

case $(uname -m) in
  arm64|aarch64)
    QEMU_SYSTEM=qemu-system-aarch64
    MACHINE=virt
    QEMU_ARCH=aarch64
    ;;
  x86_64|amd64)
    QEMU_SYSTEM=qemu-system-x86_64
    MACHINE=q35
    QEMU_ARCH=x86_64
    ;;
  *)
    printf 'Unsupported host architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

source "$PROJECT_DIR/scripts/qemu-firmware.sh"
EFI_FIRMWARE=$(find_qemu_firmware "$QEMU_ARCH" || true)
if ! command -v "$QEMU_SYSTEM" >/dev/null 2>&1 || [ ! -f "$EFI_FIRMWARE" ]; then
  printf 'QEMU or UEFI firmware is unavailable. Set QEMU_EFI if necessary.\n' >&2
  exit 1
fi

if [ "$(uname -s)" = Darwin ]; then
  ACCEL_ARGS=(-accel hvf -cpu host)
  # Cocoa only permits resizing with Zoom To Fit enabled. VirtIO receives
  # the resulting UI size and advertises it as a new DRM preferred mode.
  DISPLAY_BACKEND=${QEMU_DISPLAY:-cocoa,zoom-to-fit=on}
elif [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL_ARGS=(-accel kvm -cpu host)
  DISPLAY_BACKEND=${QEMU_DISPLAY:-default}
else
  ACCEL_ARGS=(-accel tcg -cpu max)
  DISPLAY_BACKEND=${QEMU_DISPLAY:-default}
fi

CLIPBOARD_ARGS=()
if [ "$VM_CLIPBOARD" = 1 ]; then
  if ! "$QEMU_SYSTEM" -machine "$MACHINE" -chardev help 2>&1 | grep -qx '  qemu-vdagent'; then
    printf 'This QEMU build lacks qemu-vdagent clipboard support. Use a supported QEMU build or set VM_CLIPBOARD=0.\n' >&2
    exit 1
  fi
  CLIPBOARD_ARGS=(
    -device virtio-serial-pci,id=clipboard-serial
    -chardev qemu-vdagent,id=clipboard,clipboard=on,mouse=off
    -device virtserialport,chardev=clipboard,name=com.redhat.spice.0
  )
fi

exec "$QEMU_SYSTEM" \
  -name Gentoo \
  -machine "$MACHINE" "${ACCEL_ARGS[@]}" \
  -m 4096 -smp 4 \
  -bios "$EFI_FIRMWARE" \
  -drive "file=$DISK,if=virtio,format=qcow2" \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" \
  -device "virtio-net-pci,netdev=net0" \
  -device virtio-gpu-pci \
  ${CLIPBOARD_ARGS[@]+"${CLIPBOARD_ARGS[@]}"} \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display "$DISPLAY_BACKEND" -serial none -monitor none -no-reboot
