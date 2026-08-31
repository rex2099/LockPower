#!/bin/zsh
set -euo pipefail

label='io.github.lockpower.agent'
agent_file="$HOME/Library/LaunchAgents/${label}.plist"
install_dir="$HOME/Library/Application Support/LockPower"
domain="gui/$(/usr/bin/id -u)"

if [[ "$install_dir" != "$HOME/Library/Application Support/LockPower" ]]; then
    echo 'Refusing to remove an unexpected path.' >&2
    exit 1
fi

/bin/launchctl bootout "$domain" "$agent_file" 2>/dev/null || true
/usr/bin/sudo -n /usr/bin/pmset -a lowpowermode 0 || true
/usr/bin/osascript -e 'do shell script "/bin/rm -f /etc/sudoers.d/lockpower" with administrator privileges'
/bin/rm -f "$agent_file"
/bin/rm -rf "$install_dir"

echo 'LockPower removed. Low Power Mode is off.'
