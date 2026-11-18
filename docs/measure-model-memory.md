# Measure resident memory before you book it

A router books the number you give it. That number has to be the memory the model holds while it is actually serving, at the context length and the session count you intend to run. A short prompt hides most of the KV cache, and the size of the file on disk is a different number.

Sample GTT use while a long prompt is running. On the reference machine the file is under `card1`. If that path is missing, use the `mem_info_gtt_used` file that exists under `/sys/class/drm/card*/device/`. A card number that does not move during the run is the wrong card.

```bash
awk '{printf "%s %.2f GiB\n", FILENAME, $1/1024/1024/1024}' /sys/class/drm/card*/device/mem_info_gtt_used
```

Once a second for the length of the prompt:

```bash
while true; do
  date +%H:%M:%S
  awk '{printf "%s %.2f GiB\n", FILENAME, $1/1024/1024/1024}' /sys/class/drm/card*/device/mem_info_gtt_used
  sleep 1
done
```

Stop the loop with Ctrl-C. Read the peak. Book that peak plus about 1.5 GiB.

On 17 November 2026, Qwen3.8-Flash-Next Q4 at 64K context with one session peaked at **85.55 GiB** and was booked at **87 GiB**. The router ceiling on a 96 GiB GTT window is about **94 GiB**, so that booking still leaves room for a TTS model.

`memory.free_bytes` from the router's status page is space the router can still book (ceiling minus what is already booked). It is a different reading from `mem_info_gtt_used`. Measure with the sysfs file, then put the booked figure in the router config. See [localrouter on Strix Halo](localrouter.md).

MiniMax H3 and H3-Image are the exception on this machine. They book the whole ceiling. ComfyUI reads their weights into host memory before the GPU takes them, and on this APU that host memory is the same unified pool. A GTT sample taken in the middle of a job understates what has to be free before the job starts.

Back to the [guide](../README.md).
