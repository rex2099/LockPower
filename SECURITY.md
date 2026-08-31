# Security

LockPower runs as the signed-in user. It does not install a privileged daemon,
kernel extension, network listener, analytics SDK, or updater.

The installer adds one narrowly scoped sudoers rule for the signed-in user. It
permits exactly these two commands without another password prompt:

```text
/usr/bin/pmset -a lowpowermode 0
/usr/bin/pmset -a lowpowermode 1
```

The rule contains no wildcards and does not grant general passwordless sudo.
The uninstaller removes the rule and restores Low Power Mode to off.

Please report security issues through a private GitHub security advisory after
the repository is published.
