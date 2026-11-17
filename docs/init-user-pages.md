# Kernel log: init_user_pages

When ComfyUI loads a large GGUF on this GPU, the kernel log fills with `amdgpu` lines that mention `init_user_pages`. On 17 November 2026 a large load wrote about 12,000 of those lines. They finish in under a second. They are harmless.

ComfyUI 0.45 and later already turns pinned memory off on an integrated GPU. A flag in the `--disable-pinned-memory` style does not change the line count. An A/B test on this machine, one run with that kind of flag and one without, showed no difference.

Leave the kernel command line alone. The only kernel parameters in this guide are the graphics-memory ceiling in [section 4 of the install guide](../README.md#4-give-the-gpu-96-gib-for-a-local-model), and they are not a remedy for these lines.

Count the lines over a window you pick:

```bash
journalctl -k --since "5 min ago" | grep -c init_user_pages
```

`grep -c` prints how many lines matched. A burst of about 12,000 lines during one large GGUF load is the pattern from the reference machine.

Back to the [guide](../README.md).
