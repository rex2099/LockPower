#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
delay_seconds=${1:-120}
label='io.github.lockpower.agent'
install_dir="$HOME/Library/Application Support/LockPower"
app_path="$install_dir/LockPower.app"
binary_path="$app_path/Contents/MacOS/LockPower"
agent_dir="$HOME/Library/LaunchAgents"
agent_file="$agent_dir/${label}.plist"
log_file="$HOME/Library/Logs/LockPower.log"
domain="gui/$(/usr/bin/id -u)"
user_name=$(/usr/bin/id -un)
stage_dir=$(/usr/bin/mktemp -d "${TMPDIR%/}/lockpower.install.XXXXXX")

cleanup() {
    /bin/rm -rf "$stage_dir"
}
trap cleanup EXIT

if [[ ! "$delay_seconds" =~ '^[0-9]+$' ]] || (( delay_seconds < 1 || delay_seconds > 3600 )); then
    echo 'Delay must be a whole number from 1 to 3600 seconds.' >&2
    exit 2
fi

if [[ "$(/usr/bin/uname -m)" != 'arm64' ]]; then
    echo 'LockPower currently supports Apple silicon Macs only.' >&2
    exit 2
fi

/bin/zsh "$script_dir/build.sh"

stage_agent="$stage_dir/${label}.plist"
/usr/bin/plutil -create xml1 "$stage_agent"
/usr/libexec/PlistBuddy -c "Add :Label string $label" "$stage_agent"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$stage_agent"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $binary_path" "$stage_agent"
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$stage_agent"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:LOCKPOWER_DELAY_SECONDS string $delay_seconds" "$stage_agent"
/usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$stage_agent"
/usr/libexec/PlistBuddy -c 'Add :KeepAlive bool true' "$stage_agent"
/usr/libexec/PlistBuddy -c 'Add :ProcessType string Interactive' "$stage_agent"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $log_file" "$stage_agent"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $log_file" "$stage_agent"
/usr/libexec/PlistBuddy -c 'Add :ThrottleInterval integer 10' "$stage_agent"
/usr/bin/plutil -lint "$stage_agent"

stage_sudoers="$stage_dir/lockpower.sudoers"
/usr/bin/printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 0, /usr/bin/pmset -a lowpowermode 1\n' "$user_name" > "$stage_sudoers"
/bin/chmod 0600 "$stage_sudoers"
/usr/bin/install -m 0755 "$script_dir/scripts/install-privileged.sh" "$stage_dir/install-privileged.sh"

/usr/bin/osascript "$script_dir/scripts/authorize-install.applescript" \
    "$stage_dir/install-privileged.sh" "$stage_sudoers"

/bin/launchctl bootout "$domain" "$agent_file" 2>/dev/null || true
/bin/mkdir -p "$install_dir" "$agent_dir" "$HOME/Library/Logs"
/bin/rm -rf "$app_path"
/usr/bin/ditto "$script_dir/build/LockPower.app" "$app_path"
/usr/bin/install -m 0755 "$script_dir/status.sh" "$install_dir/status.sh"
/usr/bin/install -m 0755 "$script_dir/uninstall.sh" "$install_dir/uninstall.sh"
/usr/bin/install -m 0644 "$stage_agent" "$agent_file"

/bin/launchctl bootstrap "$domain" "$agent_file"
/bin/launchctl kickstart -k "$domain/$label"

echo "LockPower installed with a ${delay_seconds}-second delay."
echo "Status: $install_dir/status.sh"
echo "Uninstall: $install_dir/uninstall.sh"
