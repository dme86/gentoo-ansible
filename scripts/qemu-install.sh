#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
STATE_DIR="$PROJECT_DIR/.qemu"
CACHE_DIR="$STATE_DIR/cache"
DISK="$STATE_DIR/gentoo.qcow2"
DISK_SIZE=32G
MEMORY=4096
CPUS=4
SSH_PORT=2222
RUN_POST_INSTALL=0
KEEP_RUNNING=0
FORCE=0

usage() {
  cat <<'EOF'
Usage: scripts/qemu-install.sh [options]

Create a fresh qcow2 disk, install Gentoo through the latest native minimal
ISO, boot the disk once, and verify the resulting system over SSH.

  --disk PATH          Output qcow2 image (default: .qemu/gentoo.qcow2)
  --disk-size SIZE     qemu-img size (default: 32G)
  --memory MIB         Guest memory (default: 4096)
  --cpus COUNT         Guest CPUs (default: 4)
  --ssh-port PORT      Local forwarded SSH port (default: 2222)
  --post-install       Run post_install.yml after the first disk boot
  --keep-running       Leave the installed VM running after verification
  --force              Replace an existing output disk
  -h, --help           Show this help

Environment:
  GENTOO_ROOT_PASSWORD Password for root. A random one is generated and printed
                       when this variable is unset.
  QEMU_EFI             Override the edk2/OVMF firmware used for the disk boot.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --disk) DISK=$2; shift 2 ;;
    --disk-size) DISK_SIZE=$2; shift 2 ;;
    --memory) MEMORY=$2; shift 2 ;;
    --cpus) CPUS=$2; shift 2 ;;
    --ssh-port) SSH_PORT=$2; shift 2 ;;
    --post-install) RUN_POST_INSTALL=1; shift ;;
    --keep-running) KEEP_RUNNING=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case $(uname -m) in
  x86_64|amd64)
    GENTOO_ARCH=amd64; QEMU_ARCH=x86_64; MACHINE=q35; SERIAL_CONSOLE=ttyS0 ;;
  arm64|aarch64)
    GENTOO_ARCH=arm64; QEMU_ARCH=aarch64; MACHINE=virt; SERIAL_CONSOLE=ttyAMA0 ;;
  *)
    printf 'Unsupported host architecture: %s (supported: x86_64, arm64)\n' "$(uname -m)" >&2
    exit 1 ;;
esac

for command_name in curl qemu-img "qemu-system-$QEMU_ARCH" bsdtar ssh ssh-keygen sshpass ansible-playbook openssl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing dependency: %s\n' "$command_name" >&2
    exit 1
  fi
done

mkdir -p "$STATE_DIR" "$CACHE_DIR" "$(dirname "$DISK")"
PRIVATE_KEY="$STATE_DIR/installer_ed25519"
PUBLIC_KEY="$PRIVATE_KEY.pub"
INVENTORY="$STATE_DIR/inventory.ini"
LIVE_LOG="$STATE_DIR/live-console.log"
DISK_LOG="$STATE_DIR/disk-console.log"
PID_FILE="$STATE_DIR/qemu.pid"
QEMU_PID=

cleanup() {
  if [ -n "${QEMU_PID:-}" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
}
trap cleanup EXIT INT TERM

if [ -e "$DISK" ]; then
  if [ "$FORCE" -ne 1 ]; then
    printf 'Disk already exists: %s (use --force to replace it)\n' "$DISK" >&2
    exit 1
  fi
  rm -f "$DISK"
fi

if [ ! -f "$PRIVATE_KEY" ]; then
  ssh-keygen -q -t ed25519 -N '' -f "$PRIVATE_KEY"
fi

ROOT_PASSWORD=${GENTOO_ROOT_PASSWORD:-}
if [ -z "$ROOT_PASSWORD" ]; then
  ROOT_PASSWORD=$(openssl rand -hex 12)
  GENERATED_PASSWORD=1
else
  GENERATED_PASSWORD=0
fi
LIVE_PASSWORD=$(openssl rand -hex 12)
export ANSIBLE_CONFIG="$PROJECT_DIR/ansible.cfg"

BASE_URL="https://distfiles.gentoo.org/releases/$GENTOO_ARCH/autobuilds/current-install-$GENTOO_ARCH-minimal"
MANIFEST_URL="$BASE_URL/latest-install-$GENTOO_ARCH-minimal.txt"
MANIFEST=$(curl -fsSL "$MANIFEST_URL")
ISO_NAME=$(printf '%s\n' "$MANIFEST" | awk '/^install-.*-minimal-.*\.iso [0-9]+$/ { print $1; exit }')
if [ -z "$ISO_NAME" ]; then
  printf 'Could not determine the latest ISO from %s\n' "$MANIFEST_URL" >&2
  exit 1
fi
ISO="$CACHE_DIR/$ISO_NAME"

printf 'Using Gentoo ISO: %s\n' "$ISO_NAME"
if [ ! -f "$ISO" ]; then
  curl -fL --progress-bar "$BASE_URL/$ISO_NAME" -o "$ISO.part"
  mv "$ISO.part" "$ISO"
fi
CHECKSUM_DOCUMENT=$(curl -fsSL "$BASE_URL/$ISO_NAME.sha256")
EXPECTED_SHA256=$(printf '%s\n' "$CHECKSUM_DOCUMENT" | awk '/^[0-9a-f]{64}  / { print $1; exit }')
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256=$(sha256sum "$ISO" | awk '{print $1}')
else
  ACTUAL_SHA256=$(shasum -a 256 "$ISO" | awk '{print $1}')
fi
if [ -z "$EXPECTED_SHA256" ] || [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
  printf 'ISO SHA-256 verification failed for %s\n' "$ISO" >&2
  exit 1
fi

EXTRACT_DIR="$CACHE_DIR/${ISO_NAME%.iso}"
mkdir -p "$EXTRACT_DIR"
if [ ! -f "$EXTRACT_DIR/gentoo" ] || [ ! -f "$EXTRACT_DIR/gentoo.igz" ] || [ ! -f "$EXTRACT_DIR/grub.cfg" ]; then
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  bsdtar -xf "$ISO" -C "$EXTRACT_DIR" \
    boot/gentoo boot/gentoo.igz boot/grub/grub.cfg
  mv "$EXTRACT_DIR/boot/gentoo" "$EXTRACT_DIR/gentoo"
  mv "$EXTRACT_DIR/boot/gentoo.igz" "$EXTRACT_DIR/gentoo.igz"
  mv "$EXTRACT_DIR/boot/grub/grub.cfg" "$EXTRACT_DIR/grub.cfg"
  rmdir "$EXTRACT_DIR/boot/grub" "$EXTRACT_DIR/boot"
fi
LIVE_BOOT_ARGS=$(awk '/^[[:space:]]*linux \/boot\/gentoo / {
  sub(/^[[:space:]]*linux \/boot\/gentoo /, ""); print; exit
}' "$EXTRACT_DIR/grub.cfg" | sed 's/dokeymap[[:space:]]*//')
if [ -z "$LIVE_BOOT_ARGS" ]; then
  printf 'Could not read the live kernel arguments from the ISO GRUB config.\n' >&2
  exit 1
fi

find_firmware() {
  if [ -n "${QEMU_EFI:-}" ]; then
    [ -f "$QEMU_EFI" ] && { printf '%s\n' "$QEMU_EFI"; return; }
    return 1
  fi
  qemu_prefix=$(cd "$(dirname "$(command -v "qemu-system-$QEMU_ARCH")")/.." && pwd)
  if [ "$QEMU_ARCH" = aarch64 ]; then
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

EFI_FIRMWARE=$(find_firmware || true)
if [ -z "$EFI_FIRMWARE" ]; then
  printf 'No UEFI firmware found. Set QEMU_EFI to an edk2/OVMF code image.\n' >&2
  exit 1
fi

if [ "$(uname -s)" = Darwin ]; then
  ACCEL_ARGS=(-accel hvf -cpu host)
elif [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL_ARGS=(-accel kvm -cpu host)
else
  ACCEL_ARGS=(-accel tcg -cpu max)
fi

COMMON_ARGS=(
  -machine "$MACHINE" "${ACCEL_ARGS[@]}"
  -m "$MEMORY" -smp "$CPUS"
  -drive "file=$DISK,if=virtio,format=qcow2"
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
  -device "virtio-net-pci,netdev=net0"
  -display none -serial stdio -monitor none -no-reboot
)

wait_for_ssh_password() {
  attempt=0
  while [ "$attempt" -lt 180 ]; do
    if SSHPASS="$LIVE_PASSWORD" sshpass -e ssh \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=2 -p "$SSH_PORT" root@127.0.0.1 true >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1)); sleep 2
  done
  return 1
}

wait_for_ssh_key() {
  attempt=0
  while [ "$attempt" -lt 180 ]; do
    if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=2 \
      -p "$SSH_PORT" root@127.0.0.1 true >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1)); sleep 2
  done
  return 1
}

qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"

printf 'Booting the minimal ISO kernel...\n'
"qemu-system-$QEMU_ARCH" "${COMMON_ARGS[@]}" \
  -drive "file=$ISO,media=cdrom,if=none,id=installcd,readonly=on" \
  -device virtio-scsi-pci,id=scsi0 -device scsi-cd,drive=installcd \
  -kernel "$EXTRACT_DIR/gentoo" -initrd "$EXTRACT_DIR/gentoo.igz" \
  -append "$LIVE_BOOT_ARGS dosshd passwd=$LIVE_PASSWORD console=$SERIAL_CONSOLE,115200" \
  >"$LIVE_LOG" 2>&1 &
QEMU_PID=$!
printf '%s\n' "$QEMU_PID" > "$PID_FILE"

if ! wait_for_ssh_password; then
  printf 'Live ISO did not become reachable. See %s\n' "$LIVE_LOG" >&2
  exit 1
fi

SSHPASS="$LIVE_PASSWORD" sshpass -e ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -p "$SSH_PORT" root@127.0.0.1 \
  'umask 077; mkdir -p /root/.ssh; cat > /root/.ssh/authorized_keys' < "$PUBLIC_KEY"

cat > "$INVENTORY" <<EOF
[gentoo_live]
qemu-live ansible_host=127.0.0.1 ansible_port=$SSH_PORT ansible_user=root ansible_ssh_private_key_file=$PRIVATE_KEY ansible_python_interpreter=/usr/bin/python3

[gentoo_installed]
qemu-installed ansible_host=127.0.0.1 ansible_port=$SSH_PORT ansible_user=root ansible_ssh_private_key_file=$PRIVATE_KEY ansible_python_interpreter=/usr/bin/python3
EOF

printf 'Running the Gentoo installation playbook...\n'
GENTOO_INSTALL_PASSWORD="$ROOT_PASSWORD" ansible-playbook \
  -i "$INVENTORY" "$PROJECT_DIR/install.yml" \
  -e "installer_public_key_path=$PUBLIC_KEY"

ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -p "$SSH_PORT" root@127.0.0.1 'poweroff' >/dev/null 2>&1 || true
wait "$QEMU_PID" || true
QEMU_PID=
rm -f "$PID_FILE"

printf 'Booting the installed disk with UEFI...\n'
"qemu-system-$QEMU_ARCH" "${COMMON_ARGS[@]}" -bios "$EFI_FIRMWARE" \
  >"$DISK_LOG" 2>&1 &
QEMU_PID=$!
printf '%s\n' "$QEMU_PID" > "$PID_FILE"

if ! wait_for_ssh_key; then
  printf 'Installed system did not become reachable. See %s\n' "$DISK_LOG" >&2
  exit 1
fi

if [ "$RUN_POST_INSTALL" -eq 1 ]; then
  printf 'Running post_install.yml...\n'
  ansible-playbook -i "$INVENTORY" "$PROJECT_DIR/post_install.yml" \
    -e post_install_target=gentoo_installed
fi

VERIFY_OUTPUT=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" root@127.0.0.1 \
  'printf "%s | kernel %s | root %s\n" "$(cat /etc/gentoo-release)" "$(uname -r)" "$(findmnt -n -o FSTYPE,OPTIONS /)"')
printf 'Verified: %s\n' "$VERIFY_OUTPUT"

if [ "$KEEP_RUNNING" -eq 1 ]; then
  trap - EXIT INT TERM
  printf 'VM is running (PID %s), SSH: ssh -i %s -p %s root@127.0.0.1\n' \
    "$QEMU_PID" "$PRIVATE_KEY" "$SSH_PORT"
else
  ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p "$SSH_PORT" root@127.0.0.1 'poweroff' >/dev/null 2>&1 || true
  wait "$QEMU_PID" || true
  QEMU_PID=
fi

printf 'Gentoo disk ready: %s\n' "$DISK"
if [ "$GENERATED_PASSWORD" -eq 1 ]; then
  printf 'Generated root password (store it now): %s\n' "$ROOT_PASSWORD"
fi
