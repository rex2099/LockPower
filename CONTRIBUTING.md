# Contributing

Bug reports and focused pull requests are welcome. Please describe the macOS
version, Mac model, expected behavior, and the relevant non-sensitive lines
from `~/Library/Logs/LockPower.log`.

Before opening a pull request, run:

```sh
zsh tests/test.sh
```

Changes that widen the sudoers rule, add network access, or collect telemetry
need a clear security justification and will not be accepted by default.
