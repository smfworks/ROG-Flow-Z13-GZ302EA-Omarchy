# Root maintenance

This is the upkeep that wants root on an Omarchy install of the Flow Z13: home snapshots, a cap on core dumps, the pacman package cache, a monthly btrfs scrub, and key-only OpenSSH. The script that does it is [scripts/sudo-maint.sh](../scripts/sudo-maint.sh).

It is safe to re-run. If a file, a timer, or a snapshot is already in the desired state, that part is left as it is and reported as `ok`.

It does not install packages. It does not change the kernel, the bootloader, the BIOS, or the initramfs. It does not reboot. It does not turn on timeline snapshots for the root snapper config. `limine-snapper-sync` only acts on the `/` config, which is why that timeline stays off and home snapshots are taken by snapper's own timers.

Run it from a checkout of this repository:

```bash
sudo ./scripts/sudo-maint.sh --dry-run
sudo ./scripts/sudo-maint.sh
```

`--dry-run` prints the plan and the same style of closing checks, and it writes nothing. It still has to run as root so it can read the system files it is planning to change.

`--user NAME` is the login account. Snapper's `ALLOW_USERS` and the SSH key check both use it. When you omit it, the script uses `SUDO_USER` if that is set and is not root. A root shell with no `--user` can still set core-dump caps, prune the package cache, and enable the scrub timer. Home snapshots and SSH are skipped or reported `FAIL` until an account is named. Use the placeholder `NAME` in notes. Do not write a real account name into a commit.

Every file the script changes is copied first into `/root/maint-backup-<date>/`, with a `MANIFEST` of the paths and of actions that are not files (enabling a timer, creating the baseline snapshot). `<date>` is `YYYYMMDD`. A second run on the same day uses `YYYYMMDD-HHMMSS` so the first backup stays intact. The `MANIFEST` records the login account. Leave that directory on the machine. Do not paste it into a public repository.

The run ends with one line per check: `ok`, `skip`, or `FAIL`, then `result: ok` or `result: FAIL`. `skip` is a case the script is supposed to leave alone. The process exits 0 when there is no `FAIL`, and 1 when there is.

## Home snapshots

The script treats `/home` as its own btrfs subvolume only when both of these are true: `stat -f -c %T /home` prints `btrfs`, and `stat -c %i /home` prints `256`. Inode 256 is the root of a btrfs subvolume. Anything else is a `skip`, and the rest of the script continues.

When `/home` is a subvolume and `snapper` is installed:

1. `snapper -c home create-config /home` if `/etc/snapper/configs/home` does not exist yet.
2. `SNAPPER_CONFIGS` in `/etc/conf.d/snapper` gains `home` if Omarchy's snapper repair has reset that list to `root`. The config file can still be on disk after that repair. Re-run this script after a large Omarchy update.
3. The home config is set to:
   - `TIMELINE_CREATE=yes`
   - `TIMELINE_CLEANUP=yes`, so the limits below are applied by `snapper-cleanup.timer`
   - hourly 6, daily 7, weekly 4, monthly 2, yearly 0 (`TIMELINE_LIMIT_HOURLY` through `TIMELINE_LIMIT_YEARLY`)
   - `NUMBER_LIMIT=10`
   - `FREE_LIMIT=0.25` (cleanup may drop snapshots to keep about a quarter of the filesystem free)
   - `ALLOW_USERS` includes the login account. An account already listed is left there.
   - `SYNC_ACL=yes`, so that account can read the snapshot directory
4. `snapper-timeline.timer` and `snapper-cleanup.timer` are enabled and started.
5. A snapshot described as `baseline` is created if one is not already there. It is created with no cleanup algorithm, so the hourly and number limits do not delete it.

If `snapper` is missing, the check is `FAIL` and the script does not install it.

A plain directory of model weights is inside these snapshots. Deleting the models does not free the space until the snapshots that contain them expire. On a new install, create model directories as nested subvolumes before you put files in them. [Pin model weights](pin-model-weights.md) has the command. This script does not convert an existing directory.

Snapshots are not a spare copy of the disk. A dead SSD takes the snapshots with it.

## Core dump caps

The script writes `/etc/systemd/coredump.conf.d/50-caps.conf`:

```
[Coredump]
ProcessSizeMax=2G
ExternalSizeMax=2G
MaxUse=5G
```

Then it runs `systemctl daemon-reload`. A core dump from a large GPU process then stops at those caps. No reboot is required. If the file already matches, it is left alone.

## Package cache

If `/var/lib/pacman/db.lck` exists, pacman is in the middle of something and this whole step is skipped. Re-run when the lock is gone.

Otherwise, if `paccache` is on `PATH` (it comes from `pacman-contrib`), the script runs `paccache -rk2`, which keeps the two newest versions of each cached package. It then runs `systemctl enable --now paccache.timer` so that prune repeats. Packages `paccache` deletes are not in the backup directory. With `--dry-run` the script runs `paccache -rk2 -d`, which lists what would be removed and deletes nothing. Read that list before the first real run.

If `paccache` or its timer unit is not installed, the step is `skip`. The script does not install `pacman-contrib`.

## btrfs scrub

`systemctl enable --now btrfs-scrub@-.timer` turns on the monthly scrub of `/`. One scrub of that filesystem covers every subvolume on it, including `/home`. The script does not add a timer per subvolume.

If `/` is not btrfs, or the timer unit is not installed, the step is `skip`.

## SSH key-only

This step runs only when all of the following are true:

- `sshd` is installed, and `/etc/ssh/sshd_config` includes `/etc/ssh/sshd_config.d/*.conf`.
- A login account was named, as above.
- `ssh-keygen -l -f ~/.ssh/authorized_keys` for that account lists at least one key. The script uses that account's home, not root's.
- `~`, `~/.ssh`, and `authorized_keys` are owned by that account, are not symlinks, and are not writable by group or other. That is the mode `sshd` will accept. The script does not chmod them for you.

It writes `/etc/ssh/sshd_config.d/50-no-password.conf`:

```
PasswordAuthentication no
KbdInteractiveAuthentication no
```

Then it runs `sshd -t`. If the test fails, the file is restored from the backup (or removed, if it was new) and `sshd` is not reloaded. If the test passes, the script runs `systemctl reload sshd` (or `ssh`, if that is the unit name on the machine).

Open a new key login and confirm it works before you close the session you already have. Tailscale SSH is a separate path and is not changed by this file.

If `50-no-password.conf` already exists and its contents differ, the script does not overwrite it. If the drop-in is already the key-only file but the account's keys are no longer usable, the check is `FAIL` and the drop-in stays. The script will not turn passwords back on by itself.

If there is no usable key, the step is `skip` and passwords stay as they are.

## Undo

Copy a changed file back from the backup directory named in that run's `MANIFEST`, then:

- core dumps: `sudo systemctl daemon-reload`
- SSH: restore or remove the drop-in, run `sshd -t`, and reload `sshd` only if the test passes
- timers you want off: `sudo systemctl disable --now <timer>`
- a home config this script created, and that you want gone: `sudo snapper -c home delete-config` also deletes the home snapshots. Restore the config file instead if you want the snapshots kept.

`paccache -rk2` cannot be undone from the backup.

## Closing checks

A clean machine that already matches, or a dry-run of a machine this script can finish, ends like this:

```
-- checks --
ok    home snapshots: ...
ok    root snapper timeline: TIMELINE_CREATE=no; left unchanged (limine-snapper-sync only acts on /)
ok    coredump caps: ProcessSizeMax=2G ExternalSizeMax=2G MaxUse=5G
ok    paccache: kept 2 package versions; paccache.timer enabled
ok    btrfs scrub: btrfs-scrub@-.timer enabled (one monthly scrub of / covers every subvolume)
ok    ssh key-only: PasswordAuthentication no, KbdInteractiveAuthentication no. ...
result: ok
```

`skip` on home snapshots is the normal result when `/home` is not its own subvolume. Read a `FAIL` line before you re-run. The script will not paper over a failed `sshd -t` or a missing `snapper` by installing software or by rebooting.

Back to the [guide](../README.md).
