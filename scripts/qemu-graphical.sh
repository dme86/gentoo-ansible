#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DISK=${1:-"$PROJECT_DIR/.qemu/gentoo.qcow2"}
SSH_PORT=${SSH_PORT:-2222}

if [ ! -f "$DISK" ]; then
  printf 'QEMU disk not found: %s\n' "$DISK" >&2
  exit 1
fi

case $(uname -m) in
  arm64|aarch64)
    QEMU_SYSTEM=qemu-system-aarch64
    MACHINE=virt
    DEFAULT_EFI=/opt/homebrew/share/qemu/edk2-aarch64-code.fd
    ;;
  x86_64|amd64)
    QEMU_SYSTEM=qemu-system-x86_64
    MACHINE=q35
    DEFAULT_EFI=/opt/homebrew/share/qemu/edk2-x86_64-code.fd
    ;;
  *)
    printf 'Unsupported host architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

EFI_FIRMWARE=${QEMU_EFI:-$DEFAULT_EFI}
if ! command -v "$QEMU_SYSTEM" >/dev/null 2>&1 || [ ! -f "$EFI_FIRMWARE" ]; then
  printf 'QEMU or UEFI firmware is unavailable. Set QEMU_EFI if necessary.\n' >&2
  exit 1
fi

if [ "$(uname -s)" = Darwin ]; then
  ACCEL_ARGS=(-accel hvf -cpu host)
elif [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL_ARGS=(-accel kvm -cpu host)
else
  ACCEL_ARGS=(-accel tcg -cpu max)
fi

exec "$QEMU_SYSTEM" \
  -machine "$MACHINE" "${ACCEL_ARGS[@]}" \
  -m 4096 -smp 4 \
  -bios "$EFI_FIRMWARE" \
  -drive "file=$DISK,if=virtio,format=qcow2" \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" \
  -device "virtio-net-pci,netdev=net0" \
  -device virtio-gpu-pci \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display default -serial none -monitor none -no-reboot
