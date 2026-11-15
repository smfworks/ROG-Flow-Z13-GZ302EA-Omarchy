# Omarchy Linux on the ASUS ROG Flow Z13 (GZ302EA)

This is a plain-language guide to setting up [Omarchy Linux](https://omarchy.org/) on the 2025 ASUS ROG Flow Z13, model **GZ302EA** — the one with the AMD Ryzen AI MAX+ 395 processor and Radeon 8060S graphics.

It is based on a working install that was checked on 15 November 2026. The original setup notes were written by Grok Build. SMF Works turned those notes into this guide.

If you are an AI coding agent applying this setup on a fresh install, start with [AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md) instead. That file is written for a careful, step-by-step implementation, including checks and rollback notes.

## Who this is for

You have this same model of machine, or you are about to install Omarchy on one, and you want it to boot reliably, use the folio keyboard and touchpad the way you expect, and have enough graphics memory to run a large local AI model.

A few things to keep in mind before you copy any command:

- These steps are for the **GZ302EA** specifically. Other Flow Z13 years and model numbers can differ in the BIOS, the keyboard, and the graphics.
- The memory numbers later in this guide come from a **128 GB** machine. If yours has less RAM, do not copy the 96 GiB graphics-memory ceiling as-is.
- Omarchy already takes care of the keyboard, the touchpad, and the usual ROG pieces during installation. The extra work on this computer was a disk check, a graphics-memory tweak for local models, and installing ROCm (AMD's compute software).
- Leave the BIOS "GPU memory" setting at **4 GB**. That sounds small, but it is the right choice here. Section 3 explains why.

## What you need

- An ASUS ROG Flow Z13, model GZ302EA
- The Omarchy installer from [omarchy.org](https://omarchy.org/)
- The folio keyboard attached when you power the machine on. You type the disk password before the desktop starts, so the keyboard has to be there from the beginning.
- A keyboard layout that can type Latin letters. This machine uses **US**. That matters at the disk-unlock screen, not just later in the desktop.
- Time and disk space for the ROCm download. It is several gigabytes.

You do not need to raise the BIOS graphics-memory reservation, and you do not need to flash or rewrite firmware.

## The machine this was checked on

These are the facts from the working install, so you can compare them to yours.

| Item | Value |
|---|---|
| Product | ASUS ROG Flow Z13 GZ302EA |
| BIOS | GZ302EA.311, dated 2025-08-01 |
| CPU | AMD Ryzen AI MAX+ 395, 16 cores / 32 threads |
| GPU | Radeon 8060S, PCI id `1002:1586`, ROCm name `gfx1151`, 40 compute units |
| NPU | Strix Halo (`aie2p`) |
| Memory | 128 GB unified LPDDR5X, soldered. Linux sees about 121.5 GiB |
| Wi-Fi | MediaTek MT7925 (Wi-Fi 7) |
| SSD | Crucial P310 2 TB, model `CT2000P310SSD2` |
| OS | Omarchy 4.5.0, kernel `7.2.15-1-omarchy` |
| Boot | Limine, LUKS, btrfs |

A few translations into everyday language:

- When you run `lsblk`, the 2 TB SSD shows up as **1.8T**. That is the same 2.00 TB drive measured in tebibytes (2,000,398,934,016 bytes). Nothing is missing.
- Linux sees about 121.5 GiB of the 128 GB of unified memory. The rest is held back by the hardware.
- The disk layout on the reference machine is a 2 GB EFI partition on `/boot` and one encrypted LUKS volume for the rest. The unlocked btrfs filesystem is mounted at `/`, `/home`, `/var/log`, and `/var/cache/pacman/pkg`. If you chose different options during install, do not change a working disk layout just to match this.

The product name Linux reports is `ROG Flow Z13 GZ302EA_GZ302EA`. The part that matters is **GZ302EA**.

## 1. Install Omarchy

Install from [omarchy.org](https://omarchy.org/). When the installer asks for a keyboard layout, pick one that types Latin letters. This machine uses **US**.

That is not a style preference. Omarchy keeps a non-Latin layout out of the disk-unlock prompt on purpose. The disk passphrase is Latin characters. If that prompt were in a Hebrew, Greek, Cyrillic, or Arabic layout, you could not type the password.

After the install, confirm you are on Omarchy and on the right hardware:

```bash
cat /etc/os-release
uname -r
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/bios_version
```

In plain words:

- The first command tells you the OS name and version. You want Omarchy. The reference machine was on 4.5.0.
- The second prints the kernel version. The reference machine used `7.2.15-1-omarchy`. A newer Omarchy kernel is fine; this is just a snapshot.
- The third is the product name from the firmware. You want `GZ302EA` in that name.
- The fourth is the BIOS version. The reference machine was `GZ302EA.311`. A different BIOS is not automatically a problem, but do not change BIOS settings to "match" this guide unless you know why.

## 2. Keyboard at boot, and the detachable touchpad

Omarchy already sets this up during installation on this model. You are mostly checking that the pieces are in place, not starting from scratch.

### The folio keyboard and the disk password

Attach the folio keyboard before you power on. The disk password is typed at the Plymouth prompt, which appears before the desktop starts. If the folio is detached, there is no keyboard to type with unless you have plugged in a USB one.

On this platform, Omarchy's early boot image loads the keyboard drivers and the console keymap before it asks for the passphrase. In `/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf`, the hook line contains `keyboard` and `keymap` ahead of `encrypt`. That order is the point: the keyboard has to be ready before encryption asks for the password.

`/etc/vconsole.conf` on the reference machine includes:

```
KEYMAP=us
XKBLAYOUT=us
```

That file may also have a few other standard lines (keyboard model, options, font). The two lines above are the ones that matter for typing the passphrase.

This machine has two USB4 ports. `/etc/mkinitcpio.conf.d/thunderbolt_module.conf` loads the `thunderbolt` module into the early boot image. It has to appear as a real module name in the image, not as a guessed optional name.

These hook and thunderbolt files are owned by Omarchy. If they already look right, leave them alone.

### If a later kernel update leaves the password prompt with a dead keyboard

1. Attach the folio, then power on.
2. From a working boot (a snapshot, or a USB keyboard), rebuild the early boot image:

```bash
sudo limine-update
```

That command refreshes the Limine boot entries and the early boot image. Then reboot and try the folio keyboard again at the password prompt.

### The detachable touchpad

The folio touchpad needs one extra udev rule. Without it, Linux treats the pad as an external device, so "disable while typing" never pairs it with the keyboard, and palm taps jump the cursor around.

Omarchy writes this rule only on a GZ302. The file is `/etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules`:

```
ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1a30", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
```

That product id `0b05:1a30` is the Z13 folio. It is specific to this keyboard cover. After adding the rule, reboot, or reload udev and replug the folio. On the reference machine, the rule was already present.

### asusctl

Omarchy also installs `asusctl` on ROG hardware. The reference machine had `asusctl` 6.5.0. You can confirm it with:

```bash
pacman -Q asusctl
```

## 3. Leave the BIOS GPU reservation at 4 GB

This setting is BIOS-specific. Do not raise it just because you want to run a large model.

The CPU and the GPU share one pool of memory. The BIOS "GPU memory" or UMA frame buffer setting does not create extra memory. It only decides how much of that shared pool is hidden from Linux and reported as dedicated graphics memory.

On the reference machine, the kernel log shows `VRAM: 4096M`. Leave it at **4 GB**.

On a 128 GB Z13, ASUS can reserve 0.5, 1, 2, 4, 8, 16, 32, 64, or 96 GB. In Windows, that control lives in Armoury Crate, under **System Settings**, then **Free up memory**. A 96 GB reservation would leave Linux with roughly 32 GB. You do not need that. The GPU can still reach a large model with the BIOS left at 4 GB. The next section is how.

If you boot into the BIOS to look, you are only confirming the value. This guide does not include a firmware update, and it does not ask you to change other BIOS settings.

## 4. Give the GPU 96 GiB for a local model

This step is for a **128 GB** GZ302EA, and it changes kernel boot parameters. Read it before you apply it.

With the BIOS left at 4 GB, the GPU's shared window (called GTT) defaults to about half of the RAM Linux can see. On the reference machine, that default is **60.7 GiB**. A model that must run on the 8060S needs that ceiling raised. The memory stays available to the desktop until a model actually allocates it. You are not setting 96 GiB aside up front.

Create `/etc/limine-entry-tool.d/gpu-llm.conf` and refresh the boot entries:

```bash
sudo tee /etc/limine-entry-tool.d/gpu-llm.conf >/dev/null <<'EOF'
# Ceiling for Radeon 8060S unified memory. Not reserved until a model allocates it.
KERNEL_CMDLINE[default]+=" amdgpu.gttsize=98304 ttm.pages_limit=25165824"
EOF
sudo limine-update
```

Then reboot.

What those numbers mean:

- `98304` is 96 GiB.
- `25165824` is the same amount, counted in 4 KiB pages.
- With a 96 GiB model loaded, about 25 GiB remains for the desktop.

If you would rather have a 104 GiB ceiling, use `amdgpu.gttsize=106496` and `ttm.pages_limit=27262976` instead. That leaves about 17 GiB for the desktop. The commands above install the 96 GiB ceiling, which is what the reference machine uses.

After the reboot, confirm:

```bash
awk '{printf "GTT %.1f GiB\n", $1/1024/1024/1024}' /sys/class/drm/card1/device/mem_info_gtt_total
cat /sys/module/ttm/parameters/pages_limit
```

A working result is:

```
GTT 96.0 GiB
25165824
```

`/proc/cmdline` should also contain `amdgpu.gttsize=98304` and `ttm.pages_limit=25165824`. You can check with:

```bash
grep -o 'amdgpu.gttsize=[^ ]*\|ttm.pages_limit=[^ ]*' /proc/cmdline
```

On the reference machine, the GTT size file was under `card1`. If that exact path is missing on yours, look for `mem_info_gtt_total` under `/sys/class/drm/card*/device/` and use the path that exists. Do not change the kernel parameters just because the card number is different.

To actually run the model on the GPU:

- Use a **Vulkan** build of llama.cpp (Mesa RADV). The device name looks like `Radeon 8060S Graphics (RADV GFX1151)`.
- Offload every layer. In llama.cpp that flag is `-ngl 99`.
- A CPU build ignores this graphics-memory window and uses system RAM instead.

One more pitfall: zram on this machine is about 121.5 GiB, and it is compressed RAM. It is not a second pool of memory for the model. Do not count zram as extra space for a 96 GiB model.

If you want to undo this step, see the rollback notes in [AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md). The short version is: remove `/etc/limine-entry-tool.d/gpu-llm.conf`, run `sudo limine-update`, and reboot.

## 5. Install ROCm

The `amdgpu` driver is already in the Omarchy kernel. ROCm is the userspace compute stack that some tools use to talk to the GPU. On the reference machine this was ROCm **7.2.4**, which ships `gfx1151` kernels for the 8060S. A later 7.x package from the same repos is fine if that is what `pacman` offers now.

```bash
sudo pacman -S --needed rocm-hip-sdk rocm-opencl-sdk rocm-smi-lib
sudo usermod -aG render,video "$USER"
```

The first command installs the ROCm packages if they are not already there (`--needed` means it will not reinstall them for no reason). The download is several gigabytes. The second command adds your user account to the `render` and `video` groups so you can use the GPU for compute. `$USER` is your current account. You do not need to type your username.

Log out of the desktop and back in so the group membership and `PATH` apply. `/etc/profile.d/rocm.sh` adds `/opt/rocm/bin` to your command path, and `/etc/ld.so.conf.d/rocm.conf` adds `/opt/rocm/lib`. Those files come with the packages.

Then check:

```bash
rocminfo | grep -E 'Marketing Name|Name:|gfx1151|Device Type'
/opt/rocm/bin/rocminfo --support 2>/dev/null | head
cat /opt/rocm/.info/version
```

`rocminfo` should list:

- CPU: AMD Ryzen AI MAX+ 395
- GPU: `gfx1151`, AMD Radeon 8060S Graphics, chip `1002:1586`
- NPU: Strix Halo

`/opt/rocm/bin/rocminfo` works even before the new login. A reboot is optional. ROCm itself does not need one.

On the reference machine, ROCm was installed and could see the GPU. For llama.cpp token generation on this GPU, start with the Vulkan build from the previous section. Use the ROCm or HIP build when a tool requires it.

## 6. Optional software installed on the reference machine

These are not required for the hardware. The versions below are what was installed on the reference machine on 15 November 2026. Skip this section if you only want the machine to work.

**Grok Bot** comes from the Omarchy repo:

```bash
omarchy pkg add grok-bot
```

That installed `grok-bot` 1.1.0-1. Launch it from the app menu or run `grok-bot`, then sign in. It is the Grok Bot desktop app, separate from the `grok` terminal agent.

**Cursor** is the package `cursor-bin`:

```bash
sudo pacman -S --needed cursor-bin
```

That installed `cursor-bin` 3.30.14 and its Electron dependency. Launch **Cursor**, or run `cursor`.

**Tailscale** was already installed on the reference machine. If you use Tailscale and want this computer on your tailnet:

```bash
sudo systemctl enable --now tailscaled
sudo tailscale up
```

The first command starts the Tailscale service and sets it to start at boot. The second connects this computer. Open the login link the command prints. `tailscale status` then shows this host online. Do not paste that login link, your tailnet name, or any IP addresses into a public place.

## 7. A quick check that everything looks right

Run this after a new install, or any time you want a sanity check:

```bash
# Hardware
cat /sys/class/dmi/id/product_name
lsblk -d -o NAME,SIZE,MODEL
free -h

# Keyboard and touchpad files from the Omarchy install
grep -n keyboard /etc/mkinitcpio.conf.d/00-omarchy-hooks.conf
cat /etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules

# GPU memory window
grep -o 'amdgpu.gttsize=[^ ]*\|ttm.pages_limit=[^ ]*' /proc/cmdline
awk '{printf "GTT %.1f GiB\n", $1/1024/1024/1024}' /sys/class/drm/card1/device/mem_info_gtt_total

# ROCm
cat /opt/rocm/.info/version
rocminfo | grep gfx1151
```

Expected shape of the results, on a machine like the reference one:

- Product name contains `GZ302EA`
- A `CT2000P310SSD2` near 1.8T (your SSD model may differ; the size showing a little under the advertised terabytes is normal)
- About 121 GiB visible RAM on a 128 GB unit
- The touchpad udev rule present
- GTT at 96.0 GiB if you applied section 4
- ROCm reporting `gfx1151` (7.2.4 on the reference machine)

## Troubleshooting

**The disk-password prompt ignores the folio keyboard.** Attach the folio, then power on. If a kernel update broke this, boot from a snapshot or a USB keyboard and run `sudo limine-update`, then reboot. Confirm that `/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf` still has `keyboard` and `keymap` before `encrypt`, and that `/etc/vconsole.conf` still has `KEYMAP=us` (or another Latin layout that can type your passphrase).

**The cursor jumps when you type, or "disable while typing" does nothing.** Check that `/etc/udev/rules.d/99-omarchy-asus-z13-touchpad.rules` exists and contains the `0b05:1a30` rule above. If you just added it, reboot, or reload udev and replug the folio. This product id is the Z13 folio.

**After section 4, GTT is still about 60.7 GiB, or the new parameters are missing from `/proc/cmdline`.** Make sure `/etc/limine-entry-tool.d/gpu-llm.conf` exists, run `sudo limine-update` again, and reboot. The new ceiling only applies after a reboot.

**The GTT check file `/sys/class/drm/card1/device/mem_info_gtt_total` is missing.** On the reference machine the GPU showed up as `card1`. Look under `/sys/class/drm/card*/device/mem_info_gtt_total` and use the path that exists.

**`rocminfo` does not see `gfx1151`, or you cannot access the GPU as a regular user.** Confirm the packages are installed, then confirm your account is in the `render` and `video` groups. Group changes apply after a logout and login, not immediately in an already-open terminal. `/opt/rocm/bin/rocminfo` can still be run by path before the new login.

**A local model runs slowly, or it seems to ignore the 96 GiB window.** Use a Vulkan build of llama.cpp, offload every layer with `-ngl 99`, and make sure you are not on a CPU-only build. Do not treat zram as extra model memory.

**You are tempted to set BIOS GPU memory to 96 GB.** Don't, at least not for the reasons in this guide. That reservation would hide a huge amount of memory from Linux. Section 4 raises the shared window instead, and only uses the memory when a model allocates it.

## Credit and license

The original setup notes for this machine were written by Grok Build. This public guide and the companion agent instructions were prepared by SMF Works.

This repository is released under the MIT License. See [LICENSE](LICENSE) and [ATTRIBUTION.md](ATTRIBUTION.md).
