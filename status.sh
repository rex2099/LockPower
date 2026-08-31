#!/bin/zsh
set -euo pipefail

label='io.github.lockpower.agent'
domain="gui/$(/usr/bin/id -u)"
log_file="$HOME/Library/Logs/LockPower.log"

if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
    echo 'Service: running'
else
    echo 'Service: not running'
fi

mode=$(/usr/bin/pmset -g custom | /usr/bin/awk '
    /AC Power:/ { in_ac = 1; next }
    in_ac && /lowpowermode/ { print $2; exit }
')

if [[ "$mode" == '1' ]]; then
    echo 'Low Power Mode: on'
elif [[ "$mode" == '0' ]]; then
    echo 'Low Power Mode: off'
else
    echo 'Low Power Mode: unknown'
fi

if [[ -f "$log_file" ]]; then
    echo 'Recent events:'
    /usr/bin/tail -n 8 "$log_file"
fi
