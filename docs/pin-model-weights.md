# Pin model weights

A cache cleanup will delete a file that a tool still names in its config. Keep a copy the router owns, record the hash, and point the tool at that copy.

`/home` on this install is btrfs. `cp --reflink=auto` makes a second directory entry that shares the original's disk blocks until one of them is written. Deleting the cache then leaves the pinned copy in place.

```bash
mkdir -p ~/models/pinned/<name>
cp --reflink=auto <download>/<file> ~/models/pinned/<name>/
sha256sum ~/models/pinned/<name>/*
```

`<name>` is the model, and `<download>` is the directory the file was fetched into. Use your own paths. `~` is the right way to write a home directory in notes you might publish.

Compare the hash with the Hugging Face API. A public model that is not gated needs no token. If the API asks you to log in, do that outside this note. Do not put a token on the command line, in `pin.json`, or in a shell history you later commit.

```bash
curl -fsSL "https://huggingface.co/api/models/<org>/<repo>/revision/<revision>"
```

Each entry under `siblings` has `rfilename`. A large file also has `lfs.sha256`. That is the hash `sha256sum` prints. Write `pin.json` beside the weights:

```json
{
  "source": "huggingface",
  "repo": "<org>/<repo>",
  "revision": "<commit sha from the API>",
  "files": [
    {
      "path": "<file>",
      "sha256": "<sha256sum of the pinned file>"
    }
  ]
}
```

Point the tool at `~/models/pinned/<name>`. In the localrouter Strix Halo profile the model paths are the `*_DIR` variables in `deploy/strix-halo/env.sh`. Override them in a site file that stays on the machine. Do not commit a site file.

When you move to a new revision, download that revision, write a new `pin.json`, and only then change the path the tool uses. If `sha256sum` and `lfs.sha256` disagree, stop and find out which copy is wrong before you book the model.

A plain directory under `/home` is inside the home snapper snapshots. Deleting a pinned model does not free that disk space until the snapshots that contain it expire. On a new install, create the model directory as a nested subvolume before any weights go into it:

```bash
btrfs subvolume create ~/models
```

The path must not exist yet. Nested subvolumes are left out of the parent snapshot. If the account is not allowed to create a subvolume, root can create it and `chown` it to the login account so the files are not owned by root. Leave an existing weight directory as it is. Converting it is a separate copy, and this note does not do that copy.

Snapshots are not a copy you can take to another disk. See [root maintenance](root-maintenance.md).

Back to the [guide](../README.md).
