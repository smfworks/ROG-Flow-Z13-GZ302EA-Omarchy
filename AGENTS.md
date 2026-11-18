# Agent rules for this machine

You are an AI coding agent on an Omarchy install of the **ASUS ROG Flow Z13, model GZ302EA** (128 GB unified memory, Radeon 8060S, `gfx1151`, about 96 GiB GTT). Humans start with [README.md](README.md). The first-install sequence, with its checks and rollback, is [AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md). This file is the rule set for work after that, and for anything you do while you are in the middle of it.

Follow the written procedure for the task. Do not invent a boot, firmware, or storage step.

## Safe

- Read-only checks come first. Make a change only in the step that calls for it, and make that step safe to re-run.
- Prefer a user service. The Strix Halo localrouter profile runs as a transient systemd user unit.
- Measure GTT during a real prompt before you book a model. Book the peak plus about 1.5 GiB. The procedure is [docs/measure-model-memory.md](docs/measure-model-memory.md).
- Restart only the service you changed. Restart localrouter only when `/v1/status` shows no tool in `loading`, `committing`, or `busy`.
- Before you replace a running localrouter build, write a rollback kit: the current binary, the git commit, the config, the unit file or the `env.sh` and site file that start it, and a short README that says how to put them back. [docs/localrouter.md](docs/localrouter.md) has the order.
- Root upkeep goes through [scripts/sudo-maint.sh](scripts/sudo-maint.sh). Run `sudo ./scripts/sudo-maint.sh --dry-run` first, and apply it when the owner asked. Omit `--user` when `sudo` already carries the login account. If you do pass `--user`, the name stays in that shell. Do not copy it into a file you commit.
- After a change, run that procedure's check and report `ok` or `FAIL` in a short list.
- `uv cache prune` is the cache cleanup. See [docs/uv-cache.md](docs/uv-cache.md).
- `asusctl battery limit 80` is how the charge limit is set. See [docs/battery-charge-limit.md](docs/battery-charge-limit.md).

## Not safe

- BIOS, firmware, kernel command-line parameters, Limine, mkinitcpio, and the initramfs stay as they are unless the owner asked and the step is already written in [AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md). Do not add a new one. `init_user_pages` log lines are not a reason to add one. See [docs/init-user-pages.md](docs/init-user-pages.md).
- Do not reboot unless the owner asked.
- Do not print, log, or commit secrets, tokens, passwords, keys, Wi-Fi names, serial numbers, MAC addresses, IP addresses, hostnames, tailnet names, or home paths other than `~`. Do not name an agent profile. The organization is SMF Works. Do not name an employer.
- Do not add package installation to [scripts/sudo-maint.sh](scripts/sudo-maint.sh), and do not install a package yourself to turn one of its `skip` lines into `ok`.
- Do not run `uv cache clean` unless the owner asked.
- Do not book a model from a file size, a short prompt, or `memory.free_bytes`. `memory.free_bytes` is unbooked ceiling, not a measurement of the model.
- Do not restart or unload a tool that is `loading`, `committing`, or `busy` to clear `insufficient_memory`. Idle tools unload by priority. A higher-priority idle chat model stays until you `POST /v1/tools/<id>/unload` or the owner tells you to.
- Do not edit `/etc/asusd/asusd.ron` by hand.
- Do not turn on `TIMELINE_CREATE` for the root snapper config. `limine-snapper-sync` only acts on `/`.
- Do not delete snapper snapshots to free model space unless the owner asked. Say which snapshots hold the space.
- Do not create or delete btrfs subvolumes except the two cases already written: snapper's own `.snapshots` when the owner asked you to run the maintenance script, and a new empty model directory as a nested subvolume when the owner asked. See [docs/pin-model-weights.md](docs/pin-model-weights.md).
- Do not close the SSH session that is still open after the key-only drop-in is installed. Tell the owner to test a new key login first. Tailscale SSH is unchanged.
- The 96 GiB GTT numbers are for a 128 GB unit (about 121 GiB visible). Stop and ask on any other size.

If a check fails and the procedure does not say what to do, stop and ask. Do not improvise around boot, firmware, or storage.

## Where each procedure lives

| Task | Procedure |
|---|---|
| First install, keyboard, GTT ceiling, ROCm | [AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md) and [README.md](README.md) |
| Battery charge limit | [docs/battery-charge-limit.md](docs/battery-charge-limit.md) |
| `init_user_pages` kernel lines | [docs/init-user-pages.md](docs/init-user-pages.md) |
| Book a model's memory | [docs/measure-model-memory.md](docs/measure-model-memory.md) |
| Pin weights against the Hugging Face API | [docs/pin-model-weights.md](docs/pin-model-weights.md) |
| uv cache | [docs/uv-cache.md](docs/uv-cache.md) |
| Snapshots, core dumps, paccache, scrub, SSH keys | [docs/root-maintenance.md](docs/root-maintenance.md), [scripts/sudo-maint.sh](scripts/sudo-maint.sh) |
| localrouter on this GPU | [docs/localrouter.md](docs/localrouter.md) |

## Verification checklist

Before you finish a session on this machine:

1. The diff and the transcript you would commit contain no secret, token, account name, hostname, IP, MAC, serial, Wi-Fi name, or tailnet name. Home paths are `~`.
2. You did not reboot, and you did not change BIOS, kernel parameters, Limine, mkinitcpio, or the initramfs, unless the owner asked and the step was the one in the first-install sequence.
3. The service you restarted is the one you changed, it was idle first, and its health check passed (`/health` and `/v1/status` for localrouter).
4. Any memory figure you booked came from a GTT sample at the real context and session settings, plus about 1.5 GiB. MiniMax H3 and H3-Image book the whole ceiling, as [docs/localrouter.md](docs/localrouter.md) describes.
5. A router swap has a rollback kit from before the swap.
6. If you ran `scripts/sudo-maint.sh`, the closing lines are `ok` or an explained `skip`, `result: ok`, and you did not ignore a `FAIL`.
7. Report the pass/fail list. Name any stop-and-ask you hit.
