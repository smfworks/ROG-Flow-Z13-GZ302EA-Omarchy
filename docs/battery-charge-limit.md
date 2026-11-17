# Battery charge limit

The Flow Z13 spends a lot of time on the charger. A charge limit of 80 percent keeps the battery from sitting at full.

```bash
asusctl battery limit 80
```

That command sets the limit in sysfs and saves it in `/etc/asusd/asusd.ron`. `asusd` applies the saved value again on boot. You do not add a unit of your own for this, and you do not edit the `.ron` file by hand. Run `asusctl` again if you want a different number.

Check the live value:

```bash
cat /sys/class/power_supply/BAT*/charge_control_end_threshold
```

A working result is `80`. The `BAT*` glob is this machine's battery. If the file is missing or the value did not change, `asusd` did not apply the command. Check `systemctl status asusd`, then run `asusctl battery limit 80` again.

Checked on 17 November 2026. The reference machine's `asusctl` is 6.5.0, which is what Omarchy installs on this model.

Back to the [guide](../README.md).
