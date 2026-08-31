# LockPower

LockPower automatically enables macOS Low Power Mode after you lock the screen
or the display sleeps, then restores full performance as soon as you unlock.
It is designed for always-on Apple silicon desktops such as Mac mini and Mac
Studio that still need to remain reachable for remote access.

## Why

An idle Apple silicon Mac is already efficient. The useful part of LockPower is
limiting power and heat spikes from unattended background work without putting
the Mac to sleep. Your Mac stays online; heavy work may run more slowly while
the screen is locked.

## Requirements

- Apple silicon Mac
- macOS Sequoia 15.1 or later
- An administrator account for the one-time installation prompt

## Install

```sh
git clone https://github.com/rex2099/LockPower.git
cd LockPower
./install.sh
```

The default delay is 120 seconds. To use a different delay:

```sh
./install.sh 300
```

Allowed values are 1 through 3600 seconds. Running the installer again updates
the installation and delay.

## Check status

```sh
"$HOME/Library/Application Support/LockPower/status.sh"
```

The log is stored locally at `~/Library/Logs/LockPower.log`.

## Uninstall

```sh
"$HOME/Library/Application Support/LockPower/uninstall.sh"
```

Uninstalling stops the service, turns Low Power Mode off, removes the scoped
administrator authorization, and deletes the installed files.

## What it changes

LockPower changes only the system Low Power Mode setting. It does not modify:

- system sleep or display timeout
- disk sleep
- Wake for network access
- Screen Sharing, SSH, or other remote-access settings

The installer grants passwordless access to exactly two `pmset` commands. See
[SECURITY.md](SECURITY.md) for the complete security boundary.

## Build and test

```sh
./build.sh
./tests/test.sh
```

The project is a small native Objective-C program. It uses only macOS system
frameworks and has no third-party runtime dependencies, telemetry, or network
access.

## License

MIT
