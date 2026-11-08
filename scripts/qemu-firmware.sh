#!/usr/bin/env bash

find_qemu_firmware() {
  local qemu_arch=$1
  local qemu_binary qemu_link qemu_prefix candidates candidate
  if [ -n "${QEMU_EFI:-}" ]; then
    [ -f "$QEMU_EFI" ] && { printf '%s\n' "$QEMU_EFI"; return; }
    return 1
  fi
  qemu_binary=$(command -v "qemu-system-$qemu_arch") || return 1
  while [ -L "$qemu_binary" ]; do
    qemu_link=$(readlink "$qemu_binary") || return 1
    case "$qemu_link" in
      /*) qemu_binary=$qemu_link ;;
      *) qemu_binary="$(dirname "$qemu_binary")/$qemu_link" ;;
    esac
  done
  qemu_prefix=$(cd "$(dirname "$qemu_binary")/.." && pwd -P) || return 1
  if [ "$qemu_arch" = aarch64 ]; then
    candidates="$qemu_prefix/share/qemu/edk2-aarch64-code.fd
/opt/homebrew/share/qemu/edk2-aarch64-code.fd
/usr/local/share/qemu/edk2-aarch64-code.fd
/usr/share/AAVMF/AAVMF_CODE.fd
/usr/share/edk2/aarch64/QEMU_EFI.fd"
  else
    candidates="$qemu_prefix/share/qemu/edk2-x86_64-code.fd
/opt/homebrew/share/qemu/edk2-x86_64-code.fd
/usr/local/share/qemu/edk2-x86_64-code.fd
/usr/share/OVMF/OVMF_CODE.fd
/usr/share/edk2/ovmf/OVMF_CODE.fd"
  fi
  printf '%s\n' "$candidates" | while IFS= read -r candidate; do
    if [ -f "$candidate" ]; then printf '%s\n' "$candidate"; break; fi
  done
}
