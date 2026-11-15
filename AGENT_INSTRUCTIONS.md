# Agent instructions: Omarchy on the ASUS ROG Flow Z13 (GZ302EA)

These instructions are for an AI coding agent applying the same setup on a fresh Omarchy Linux install of this exact model. Humans should start with [README.md](README.md).

Follow the steps in order. Do not invent steps that are not written here. Do not apply BIOS, kernel-parameter, or udev changes on a different product.

## Rules

- This document is for the **ASUS ROG Flow Z13, model GZ302EA** only.
- Prefer read-only checks first. Make a change only in the step that calls for it.
- Keep every step idempotent: if the desired file, package, or setting is already present, leave it and record a pass.
- After every change, run that step's verification and record the result before moving on.
- Never print, log, or commit secrets, tokens, Wi-Fi names or passwords, serial numbers, MAC addresses, personal IP addresses, usernames, or login links. If a command prints a login URL (for example `tailscale up`), tell the user to open it and do not repeat the URL. Use `~` for home paths. If a hostname must appear, use a placeholder such as `z13`.
- Do not change disk partitions, LUKS, the bootloader install, or firmware. Do not flash BIOS.
- Do not rewrite Omarchy-owned hook or thunderbolt drop-in files. Verify them. If they are wrong, stop and ask.
- The 96 GiB GTT values in step 4 are for a **128 GB** unit (about 121.5 GiB visible to Linux). Do not apply them unchanged on a machine with substantially less RAM.

## Stop and ask the user before

1. Changing any BIOS or firmware setting, including GPU memory / UMA frame buffer.
2. Writing or changing kernel command-line parameters, Limine entry drop-ins, or anything under `/etc/limine-entry-tool.d/` (step 4).
3. Running `limine-update` except as specified after a file this document told you to write, or as a recovery action the user has approved for a dead keyboard at the passphrase prompt.
4. Changing `/etc/mkinitcpio.conf` or any file under `/etc/mkinitcpio.conf.d/`.
5. Changing partitions, LUKS, btrfs subvolumes, or reinstalling the bootloader.
6. Installing or enabling optional software in step 6, unless the user already asked for it.
7. Applying the 96 GiB (or 104 GiB) GTT ceiling when visible RAM is not about 121 GiB.

If a preflight or verification check fails in a way this document does not give a fix for, stop and ask. Do not improvise around boot, firmware, or storage.

## Preflight (required, read-only)

Run:

```bash
cat /etc/os-release
uname -r
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/bios_version
lsblk -d -o NAME,SIZE,MODEL
free -h
```

Pass criteria:

- `/etc/os-release` identifies Omarchy (`ID=omarchy` or `NAME="Omarchy"`). The reference machine was Omarchy 4.5.0 (`VERSION_ID="4.5.0"`). A later Omarchy 4.x release can continue; record the version.
- `product_name` contains `GZ302EA`. The reference value is `ROG Flow Z13 GZ302EA_GZ302EA`.
- Record `bios_version`. The reference value is `GZ302EA.311` (BIOS date 2025-08-01). A different BIOS is not an automatic failure. Do not change BIOS settings to match the reference. Mention the difference to the user and continue only with verification, not firmware changes.
- Record visible RAM from `free -h` and the disk from `lsblk`. The reference machine had about 121.5 GiB visible RAM and a Crucial P310 2 TB (`CT2000P310SSD2`) that `lsblk` prints as 1.8T. That 1.8T figure is the same 2.00 TB drive in tebibytes (2,000,398,934,016 bytes). A different SSD model is fine. A different RAM size is not fine for step 4 without asking.

If the product name does not contain `GZ302EA`, or the OS is not Omarchy, stop. Do not apply the rest of this document.

Do not change anything during preflight.

## Step 1 — Confirm the install

Already covered by preflight. Also record the kernel (`uname -r`). The reference kernel was `7.2.15-1-omarchy`. A different Omarchy kernel is acceptable.

Verification: preflight passed, product contains `GZ302EA`, OS is Omarchy.

Rollback: none. This step is read-only.

## Step 2 — Verify keyboard, keymap, thunderbolt, touchpad, and asusctl

Omarchy already applies these on this model during installation. Verify first. Only the touchpad udev rule is safe to add if it is missing and the product is a GZ302EA.

### 2a. Initramfs hooks and keymap (verify only)

```bash
grep -n keyboard /etc/mkinitcpio.conf.d/00-omarchy-hooks.conf
grep -n keymap /etc/mkinitcpio.conf.d/00-omarchy-hooks.conf
cat /etc/vconsole.conf
```

Pass criteria:

- The busybox/encrypt hook line in `/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf` contains `keyboard` and `keymap` ahead of `encrypt`. On the reference machine the non-Apple line is:

  `HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)`

- `/etc/vconsole.conf` contains `KEYMAP=us` and `XKBLAYOUT=us` on the reference machine. That file may also contain other standard `systemd-localed` lines (`XKBMODEL`, `XKBOPTIONS`, `FONT`). Do not rewrite the file if the KEYMAP and XKBLAYOUT are already a Latin layout that can type the disk passphrase. If the user chose a different Latin layout at install time, leave it. If the keymap is non-Latin, stop and ask; a non-Latin layout at the Plymouth passphrase prompt can make the passphrase untypeable.

If `keyboard` and `keymap` are not ahead of `encrypt`, stop and ask. Do not edit Omarchy hook drop-ins yourself.

### 2b. Thunderbolt module drop-in (verify only)

```bash
cat /etc/mkinitcpio.conf.d/thunderbolt_module.conf
```

This machine has two USB4 ports. The drop-in must load `thunderbolt` as a real module name into the early boot image when the kernel builds it as a module. On the reference machine the file checks `modinfo` and then runs `MODULES+=(thunderbolt)` (not an optional `thunderbolt?` token).

If the file is missing or does not add the real module name, stop and ask. Do not rewrite it yourself.

### 2c. Folio touchpad udev rule

```bash
cat /etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules
```

Desired file contents, exactly:

```
ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1a30", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
```

That product id `0b05:1a30` is the Z13 folio. Omarchy writes this rule only on a GZ302.

If the file already has that rule, record a pass and do not touch it.

If the file is missing and preflight confirmed `GZ302EA`, create it:

```bash
sudo tee /etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules >/dev/null <<'EOF'
ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1a30", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Ask the user to replug the folio or reboot so the rule applies. Reboot is the more reliable option.

Verification: the file exists and matches the rule above.

Rollback: if you created the file, remove it, then run `sudo udevadm control --reload-rules` and `sudo udevadm trigger`, and ask the user to replug the folio or reboot. If the file was already present, do not remove it.

### 2d. asusctl

```bash
pacman -Q asusctl
```

The reference machine had `asusctl` 6.5.0. If it is installed, record the version and continue. If it is missing, tell the user that Omarchy normally installs `asusctl` on ROG hardware, and stop and ask before installing it. Do not install it unasked.

### Recovery only: dead keyboard at the passphrase prompt

If a later kernel update leaves the passphrase prompt with a dead keyboard, and the user has approved this recovery:

1. Confirm the folio is attached at power-on, or that a USB keyboard is available.
2. From a working boot (a snapshot or USB keyboard), run `sudo limine-update`.
3. Reboot and confirm the folio can type the passphrase.

Do not run this recovery unless the user has that problem and has approved the `limine-update`.

## Step 3 — Confirm the BIOS GPU reservation is 4 GB (read-only)

Do not change BIOS settings.

```bash
dmesg -H 2>/dev/null | grep -E 'VRAM:' || journalctl -k -b | grep -E 'VRAM:'
```

Pass criteria: the kernel log shows `VRAM: 4096M` (4 GB). Leave the BIOS "GPU memory" or UMA frame buffer at **4 GB**.

On a 128 GB Z13, ASUS can reserve 0.5, 1, 2, 4, 8, 16, 32, 64, or 96 GB. In Windows that control is Armoury Crate, **System Settings**, **Free up memory**. A 96 GB reservation would leave Linux with roughly 32 GB. The GPU can reach a large model without that reservation; step 4 raises the shared window instead.

If VRAM is not 4096M, tell the user the value you found, explain that this guide wants the BIOS left at 4 GB, and stop and ask. Do not change BIOS or firmware yourself. This guide does not include a Linux BIOS menu path or a firmware update.

Rollback: none. This step is read-only.

## Step 4 — Raise the GPU shared-memory ceiling (kernel parameters)

Stop and ask before writing this file or running `limine-update`. This changes the kernel command line.

These values are for a 128 GB GZ302EA with about 121.5 GiB visible RAM. With the BIOS left at 4 GB, the default GTT window is about half of visible RAM (**60.7 GiB** on the reference machine). The 96 GiB ceiling is not reserved until a model allocates it. With a 96 GiB model loaded, about 25 GiB remains for the desktop.

If visible RAM is substantially different from ~121 GiB, stop and ask. Do not copy these numbers onto a lower-RAM machine.

Default (reference) configuration, 96 GiB:

- File: `/etc/limine-entry-tool.d/gpu-llm.conf`
- Contents:

```
# Ceiling for Radeon 8060S unified memory. Not reserved until a model allocates it.
KERNEL_CMDLINE[default]+=" amdgpu.gttsize=98304 ttm.pages_limit=25165824"
```

- `98304` is 96 GiB. `25165824` is the same amount in 4 KiB pages.

If the user asked for a 104 GiB ceiling instead, use `amdgpu.gttsize=106496` and `ttm.pages_limit=27262976`. That leaves about 17 GiB for the desktop. Otherwise use the 96 GiB values.

Idempotent check, before writing:

```bash
cat /etc/limine-entry-tool.d/gpu-llm.conf 2>/dev/null || true
grep -o 'amdgpu.gttsize=[^ ]*\|ttm.pages_limit=[^ ]*' /proc/cmdline || true
# On the reference machine this path is card1. If it is missing, use
# /sys/class/drm/card*/device/mem_info_gtt_total
awk '{printf "GTT %.1f GiB\n", $1/1024/1024/1024}' /sys/class/drm/card1/device/mem_info_gtt_total
```

If the file already has the desired parameters and, after a prior reboot, `/proc/cmdline` and GTT already match, record a pass and skip the write.

If the file is missing or differs, and the user has approved this step:

```bash
sudo tee /etc/limine-entry-tool.d/gpu-llm.conf >/dev/null <<'EOF'
# Ceiling for Radeon 8060S unified memory. Not reserved until a model allocates it.
KERNEL_CMDLINE[default]+=" amdgpu.gttsize=98304 ttm.pages_limit=25165824"
EOF
sudo limine-update
```

Then ask the user to reboot. The new ceiling does not apply until after reboot. Do not reboot without asking.

Verification after reboot:

```bash
grep -o 'amdgpu.gttsize=[^ ]*\|ttm.pages_limit=[^ ]*' /proc/cmdline
awk '{printf "GTT %.1f GiB\n", $1/1024/1024/1024}' /sys/class/drm/card1/device/mem_info_gtt_total
cat /sys/module/ttm/parameters/pages_limit
```

Pass criteria for the 96 GiB ceiling:

```
amdgpu.gttsize=98304
ttm.pages_limit=25165824
GTT 96.0 GiB
25165824
```

If `/sys/class/drm/card1/device/mem_info_gtt_total` is missing, use the `mem_info_gtt_total` path that exists under `/sys/class/drm/card*/device/`. A different card number is not a failure by itself.

Running a model on the GPU is outside the required setup, but tell the user:

- Use a Vulkan build of llama.cpp (Mesa RADV). The device name looks like `Radeon 8060S Graphics (RADV GFX1151)`.
- Offload every layer (`-ngl 99` in llama.cpp).
- A CPU build ignores this window and uses system RAM instead.
- zram on the reference machine is about 121.5 GiB and is compressed RAM. It is not a second pool for the model.

Rollback: remove the drop-in you wrote, refresh boot entries, and reboot (ask first):

```bash
sudo rm /etc/limine-entry-tool.d/gpu-llm.conf
sudo limine-update
```

Do not remove the file if you did not create or change it, unless the user explicitly wants the ceiling removed. After reboot, GTT should return to the default (about 60.7 GiB on the 128 GB reference machine), and `/proc/cmdline` should no longer contain `amdgpu.gttsize=98304` or `ttm.pages_limit=25165824`.

## Step 5 — Install ROCm

The `amdgpu` driver is already in the Omarchy kernel. ROCm is the userspace compute stack. The reference machine had ROCm **7.2.4**, which ships `gfx1151` kernels for the 8060S. Install whatever current version the Omarchy/Arch packages provide. A different 7.x patch version is acceptable; record it.

Idempotent install:

```bash
sudo pacman -S --needed rocm-hip-sdk rocm-opencl-sdk rocm-smi-lib
sudo usermod -aG render,video "$USER"
```

The download is several gigabytes. `pacman --needed` is safe to re-run. `usermod -aG` is also safe to re-run; it adds the user to those groups without removing other group memberships. Use `"$USER"` (or the logged-in account). Do not hard-code a username in a command you record publicly.

Tell the user to log out of the desktop and back in so group membership and `PATH` apply. Do not force a reboot. ROCm itself does not need one. `/etc/profile.d/rocm.sh` adds `/opt/rocm/bin`, and `/etc/ld.so.conf.d/rocm.conf` adds `/opt/rocm/lib`. Those files come with the packages; do not rewrite them if they are present.

Verification (the path form works even before the new login):

```bash
pacman -Q rocm-hip-sdk rocm-opencl-sdk rocm-smi-lib
cat /opt/rocm/.info/version
/opt/rocm/bin/rocminfo | grep -E 'Marketing Name|Name:|gfx1151|Device Type'
/opt/rocm/bin/rocminfo --support 2>/dev/null | head
id -nG
```

Pass criteria:

- Packages are installed.
- `rocminfo` lists:
  - CPU: AMD Ryzen AI MAX+ 395
  - GPU: `gfx1151`, AMD Radeon 8060S Graphics, chip `1002:1586`
  - NPU: Strix Halo
- After the user logs out and back in, `id -nG` includes `render` and `video`. If they have not logged out yet, report that the group change is pending and is not a package failure.

For llama.cpp token generation on this GPU, start with the Vulkan build from step 4. Use a ROCm or HIP build when a tool requires it.

Rollback: only if you installed ROCm in this session and the user wants it removed:

```bash
sudo pacman -Rs rocm-hip-sdk rocm-opencl-sdk rocm-smi-lib
```

If you added the user to `render` and `video` in this session and the user wants that undone, use `gpasswd -d "$USER" render` and `gpasswd -d "$USER" video` only after confirming those memberships were not already present. Do not remove the user from groups they already had.

## Step 6 — Optional software (only if the user asked)

These are not required for the hardware. Versions below are from the reference machine on 15 November 2026. Skip this entire step unless the user asked for the given package.

### Grok Bot

```bash
omarchy pkg add grok-bot
```

Reference version: `grok-bot` 1.1.0-1. Launch from the app menu or run `grok-bot`, then the user signs in. This is the Grok Bot desktop app, separate from the `grok` terminal agent. Do not capture or store sign-in credentials.

Verification: `pacman -Q grok-bot` succeeds.

### Cursor

```bash
sudo pacman -S --needed cursor-bin
```

Reference version: `cursor-bin` 3.30.14, plus its Electron dependency. Launch **Cursor**, or run `cursor`.

Verification: `pacman -Q cursor-bin` succeeds.

### Tailscale

On the reference machine, Tailscale was already installed. If the user asked to bring this computer onto their tailnet:

```bash
sudo pacman -S --needed tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Tell the user to open the login link the command prints. Do not repeat the URL, tailnet name, or IP addresses in logs or a public repository.

Verification: `tailscale status` shows this host online. Report only that it is online, not addresses.

Rollback for this step: uninstall only packages you installed, and only if the user asked. For Tailscale, `sudo tailscale down` and `sudo systemctl disable --now tailscaled` if you enabled it in this session.

## Step 7 — Final verification

Run:

```bash
cat /sys/class/dmi/id/product_name
lsblk -d -o NAME,SIZE,MODEL
free -h
grep -n keyboard /etc/mkinitcpio.conf.d/00-omarchy-hooks.conf
cat /etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules
grep -o 'amdgpu.gttsize=[^ ]*\|ttm.pages_limit=[^ ]*' /proc/cmdline
awk '{printf "GTT %.1f GiB\n", $1/1024/1024/1024}' /sys/class/drm/card1/device/mem_info_gtt_total
cat /opt/rocm/.info/version
rocminfo | grep gfx1151
```

Expected shape on a 128 GB reference-like machine after steps 4 and 5:

- Product contains `GZ302EA`
- An SSD near its advertised size (the reference `CT2000P310SSD2` prints as 1.8T)
- About 121 GiB visible RAM
- The touchpad udev rule present
- GTT at 96.0 GiB if step 4 was applied and the machine has rebooted
- ROCm reporting `gfx1151` (7.2.4 on the reference machine)

Report a short pass/fail list for each item, plus any stop-and-ask points you hit and any optional software you skipped.

## Rollback summary

| Change | How to undo |
|---|---|
| Touchpad udev rule you added | Delete `/etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules`, reload udev, replug the folio or reboot |
| GPU GTT drop-in from step 4 | Delete `/etc/limine-entry-tool.d/gpu-llm.conf`, run `sudo limine-update`, reboot |
| ROCm packages you installed | `sudo pacman -Rs rocm-hip-sdk rocm-opencl-sdk rocm-smi-lib`; remove group memberships only if you added them |
| Optional packages you installed | Remove only those packages, and only if asked |

Do not roll back Omarchy-owned hook, keymap, or thunderbolt files you did not change. Do not use BIOS changes as a rollback.

## Reference snapshot (15 November 2026)

Recorded on a working GZ302EA so you can compare, not so you must match every version:

- Product: ASUS ROG Flow Z13 GZ302EA (`ROG Flow Z13 GZ302EA_GZ302EA`)
- BIOS: GZ302EA.311, dated 2025-08-01
- CPU: AMD Ryzen AI MAX+ 395, 16 cores / 32 threads
- GPU: Radeon 8060S, PCI id `1002:1586`, ROCm name `gfx1151`, 40 compute units
- NPU: Strix Halo (`aie2p`)
- Memory: 128 GB unified LPDDR5X, soldered; Linux sees about 121.5 GiB
- Wi-Fi hardware: MediaTek MT7925 (Wi-Fi 7)
- SSD: Crucial P310 2 TB, model `CT2000P310SSD2`
- OS: Omarchy 4.5.0, kernel `7.2.15-1-omarchy`
- Boot: Limine, LUKS, btrfs (2 GB EFI on `/boot`, one LUKS volume, btrfs mounted at `/`, `/home`, `/var/log`, `/var/cache/pacman/pkg`)
- `asusctl` 6.5.0
- ROCm 7.2.4 (`rocm-smi-lib` 7.2.0-2 on the reference machine)
