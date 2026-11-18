# localrouter on Strix Halo

[localrouter](https://github.com/jayleaton/localrouter) is a local model router: one process that loads and unloads models on a GPU as requests come in. The AMD work for this machine lives on the SMF Works fork, [smfworks/localrouter](https://github.com/smfworks/localrouter), on the `amd-split` branches. The same split is upstream in jayleaton/localrouter pull requests 153–157.

Checked on 17 November 2026 on this Flow Z13: Omarchy 4.5, kernel 7.2.x, ROCm 7.2.x, Radeon 8060S (`gfx1151`), 96 GiB GTT.

| Pull request | What it adds | State that day |
|---|---|---|
| [jayleaton/localrouter#153](https://github.com/jayleaton/localrouter/pull/153) | Detect AMD GPUs (`amdgpu`, ROCm, GTT) | Merged |
| [jayleaton/localrouter#154](https://github.com/jayleaton/localrouter/pull/154) | `openai_audio`, a worker for an OpenAI-compatible audio server | Open |
| [jayleaton/localrouter#155](https://github.com/jayleaton/localrouter/pull/155) | Strix Halo profile: ROCm Whisper, pinned Gufo, gfx1151 deploy | Open |
| [jayleaton/localrouter#156](https://github.com/jayleaton/localrouter/pull/156) | ComfyUI worker, and size options | Open |
| [jayleaton/localrouter#157](https://github.com/jayleaton/localrouter/pull/157) | MiniMax H3 and H3-Image workflows | Open |
| [smfworks/localrouter#1](https://github.com/smfworks/localrouter/pull/1) | Do not evict a tool that is loading or committing | Open |
| [smfworks/localrouter#2](https://github.com/smfworks/localrouter/pull/2) | `/v1/status`, `/metrics`, size snapping, log rotation | Open |

Build a checkout that contains fork pull request 2. That pull request sits on pull request 1 and on `amd-split/5-minimax-workflows`.

The MiniMax H3 and H3-Image community licences grant nothing in the United States, the European Union, the United Kingdom, or South Korea. Those tools are opt-in. Read the licences on Hugging Face before you install the weights ([H3](https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/LICENSE), [H3-Image](https://huggingface.co/MiniMaxAI/MiniMax-H3-Image/blob/main/LICENSE)). localrouter shows the licence text and does not enforce it.

## Build and test

```bash
zig build -Doptimize=ReleaseSafe -p <dir>
zig build test
```

`-p <dir>` installs into a directory you choose. Use a directory that is not the copy the running router is executing, so a failed build does not take the live binary with it.

Do not pass `-Dnvcc`. That flag is the CUDA build. This GPU is the ROCm path, `gfx1151`. The fork pull requests above were built with Zig 0.17.0.

`deploy/strix-halo/start.sh` renders the config and starts a transient systemd **user** unit. The unit name in `deploy/strix-halo/env.sh` defaults to `localrouter-amd`. Prefer that user unit. The profile listens on `127.0.0.1:8190`. Leave the listener on loopback.

`deploy/strix-halo/status.sh` and `stop.sh` are the matching helpers. A site file (`SITE=...`) overrides paths in `env.sh` after the defaults. Keep the site file on the machine.

## Memory budget

On a 96 GiB GTT window the router ceiling is about 94 GiB. The window itself is the one from [section 4 of the install guide](../README.md#4-give-the-gpu-96-gib-for-a-local-model). This page does not add kernel parameters.

Book a model only after you have measured it at the context and session settings you will serve. The procedure is [measure resident memory](measure-model-memory.md). Qwen3.8-Flash-Next Q4 at 64K context with one session peaked at 85.55 GiB and was booked at 87 GiB. That fits in the 94 GiB ceiling beside a TTS model.

`FLASHNEXT_RESIDENT` in `deploy/strix-halo/env.sh` still defaults to 88 GiB, from an earlier measurement. After you measure, book the new peak plus about 1.5 GiB. A context-length change makes that default stale.

MiniMax H3 and H3-Image book the whole ceiling, so a request for either of them unloads every other model first. Their GTT peak is smaller than the ceiling. ComfyUI still reads the weights into host memory before the GPU allocation, and on this APU that is the same RAM. Booking the whole ceiling is what keeps that load from starting beside a chat model that will not fit.

`memory.free_bytes` on `/v1/status` is bytes the router can still book: ceiling minus what is already booked. It is not the live `mem_info_gtt_used` sample.

## Scheduler

Fork pull request 1:

- A tool that is loading, committing, or busy stays resident. The scheduler does not unload it to make room.
- Idle tools can still be unloaded, lower priority first.
- An image request does not unload a higher-priority idle chat model. If you want that memory, unload the chat model yourself:

```bash
curl -s -X POST "http://127.0.0.1:8190/v1/tools/<id>/unload"
```

- A request that cannot fit while a non-evictable tool holds its memory gets an immediate HTTP 503. `error.type` and `error.code` are both `insufficient_memory`. The body includes `retry_after` (seconds), and the response has a `Retry-After` header. Match on `type` or `code`. There is no message string to match.
- The hint is 30 seconds when `retry_after_s` is unset or 0. A blocker whose last load took longer raises it, up to 10 minutes.
- A request that will fit once a load's temporary overshoot settles waits for that load, up to the same hint, and then gets the same 503 if the load has not settled. It does not unload the tool that is loading.

## Status

Restart the router only when no tool is `loading`, `committing`, or `busy`. `idle` is a quiet moment: a restart drops idle models too, and the next request loads them again. `unloaded` needs no unload.

`/v1/tools` says `ready` for the state `/v1/status` calls `idle`.

```bash
curl -s http://127.0.0.1:8190/v1/status | jq '{memory, evictions, tools: [.tools[] | {id, state, queue_depth, last_error}]}'
```

`last_error` is `{type, code, time}`. It has no message text. `evictions` counts tools unloaded to make room, not idle timeouts and not an unload you requested yourself.

`/health` stays `{"ok":true}`.

## Prometheus

`GET /metrics` is the same snapshot as text. The series are:

- `localrouter_tool_state{tool,state}`
- `localrouter_tool_resident_bytes`
- `localrouter_memory_bytes{kind="ceiling"|"used"|"free"}`
- `localrouter_tool_queue_depth`
- `localrouter_tool_last_load_timestamp_seconds`
- `localrouter_tool_last_error_timestamp_seconds`
- `localrouter_evictions_total`

Paths, hostnames, and secrets do not appear. Tool ids are label values.

## Image and video sizes

`GET /v1/tools` lists each image or video tool's size grid (`min_width`, `max_width`, `min_height`, `max_height`, `multiple`, and `max_pixels` when the model has one).

On this GPU:

| Tool | Sides | Step |
|---|---|---|
| MiniMax H3 video | 256–1344 | multiples of 32 |
| MiniMax H3-Image | 256–2048 | multiples of 32 |

Send `"size_snap": true` and the router rounds width and height to the nearest multiple inside that grid. A tie goes to the lower multiple. `1280x720` becomes `1280x704`. `300x300` becomes `288x288`. The `size` in the response is the size that was used.

Without `size_snap`, an off-grid size is refused before the tool loads. The error names that tool's own grid.

## Logs

Each tool logs at `<data_dir>/logs/<id>.log`. The live file rotates at `log_max_bytes` (default 8 MiB) and `log_keep` older files are kept (default 3). `log_max_bytes` of 0 turns rotation off. `log_keep` of 0 keeps no previous file: the next rotation deletes the live file instead of renaming it.

## Gufo

The Gufo container is given the host timezone (`TZ`). The image does not ship zone data, so when the host has `/usr/share/zoneinfo` that directory is mounted read-only. If the directory is absent, the container stays on UTC.

## Deploy, and the rollback kit

1. In the source tree, run `zig build test`, then `zig build -Doptimize=ReleaseSafe -p <dir>` into a directory other than the one that holds the binary you are about to replace.
2. Save a rollback kit before you swap. A directory such as `~/localrouter-rollback/<date>/` should hold:
   - the binary that is running now
   - the git commit (`git rev-parse HEAD`) in a file named `commit`
   - the config the service is using
   - the unit file, or, for the transient user unit, the `env.sh` and the site file `start.sh` reads
   - a short `README` that says how to copy the binary back and start the service again
3. Read `/v1/status`. Swap and restart only the router service, and only when nothing is `loading`, `committing`, or `busy`.
4. Check both of these:

```bash
curl -fsS http://127.0.0.1:8190/health
curl -s http://127.0.0.1:8190/v1/status | jq '{memory, evictions, tools: [.tools[] | {id, state, queue_depth, last_error}]}'
```

`/health` should be `{"ok":true}`. Every tool you expect should be `unloaded` or `idle`, and `last_error` should be null unless you already know about that failure.

If the new build is wrong, put the kit's binary and config back and start the service the same way. Do not reboot the machine to roll a user service back.

Pin the weights the profile points at, so a later cache cleanup cannot remove them. See [pin model weights](pin-model-weights.md).

Back to the [guide](../README.md).
