# 🐧⚙️ Gentoo-On-Rails — Fully-Automated Install with Ansible 🚀

> **Two playbooks, one goal:**  
> Reproduce a **clean, bootable Gentoo Linux system** from a raw block device, then finish it with a sane CLI tool-set, user dotfiles, automatic binary-package trust + binhost config – all while staying **idempotent** and 100 % repeatable.

| Playbook | Stage | Highlights |
|----------|-------|------------|
| **`gentoo_install.yml`** | 🏗️ **Stage 0 → 1**  (raw disk ➜ bootable Gentoo) | GPT partitioning, Btrfs subvolumes, Stage-3 auto-fetch, bind-mounts, chroot, kernel + systemd-boot install, EFI entry *(draft)*, graceful unmount + halt |
| **`post_install.yml`**  | 🛠️ **Stage 1 → 2**  (first boot tweaks) | USE-flag tuning, binhost, make.conf baseline, package diff install, Portage sync/@world, dotfile repos, service enable, optional git pull |

---

## 📜  What happens under the hood?

### 1. Disk → Filesystem → Subvolumes
1. **GPT table** with two partitions: *512 MiB* FAT32 (ESP) + remainder Btrfs *(idempotent via `parted`)*  
2. **mkfs** – vfat & btrfs  
3. Create subvols `@` + `@home`, remount with `noatime,compress=zstd,space_cache=v2`  
4. ESP (`/boot`) + `@home` mounted separately

### 2. Stage-3 bootstrap
* Parse clearsigned `latest-stage3-*-systemd.txt` → auto-download current tarball  
* Copy host DNS, bind-mount `/proc /sys /dev` into chroot

### 3. Chroot connection plugin 🔗
Second play uses `ansible_connection=chroot` → every module works natively inside `/mnt/gentoo`

### 4. Core packages & bootloader
* Install `gentoo-kernel-bin`, `installkernel`, systemd, firmware …  
* `bootctl install` copies systemd-boot to ESP  
* *(Draft)* `efibootmgr` task creates UEFI entry (verify path/device!)

### 5. Binary-package trust (getuto) & binhost
* `app-portage/getuto` seeds `/etc/portage/gnupg`  
* NetCologne binhost auto-chooses `amd64` or `arm64`

### 6. Post-install tweaker
`post_install.yml` can be run anytime:
* Detects missing packages, writes `package.accept_keywords`, licence exceptions  
* Creates user **dan**, clones/pulls dotfiles on demand  
* Optional `-e update=true` syncs Portage & upgrades @world

### 7. Idempotence everywhere ✅
* `creates:` guards for subvols  
* `changed_when:` heuristics keep colour meaningful  
* `meta: end_play` short-circuits when nothing to do  
* Lazy `umount -l` + async shutdown prevent SSH hang

---

## ▶️  Quick start

tbc

## Inventory example

```
[gentoo]
localhost

[chroot]
localhost ansible_connection=chroot ansible_chroot_path=/mnt/gentoo
```

