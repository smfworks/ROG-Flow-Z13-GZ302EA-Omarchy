# The uv cache

`uv` keeps downloaded wheels and source trees in a cache. Two cleanup commands do different things.

`uv cache prune` removes cache entries nothing still needs. That is the safe cleanup. Use it when the cache has grown and you are not in the middle of an install.

`uv cache clean` deletes the whole cache. The next install downloads it again. Run it when a cold cache is what you want. If a job still needs the wheels that are cached now, let that job finish first.

`uv cache dir` prints the cache path. It does not delete anything.

Back to the [guide](../README.md).
