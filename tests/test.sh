#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}

for script in \
    "$project_dir/build.sh" \
    "$project_dir/install.sh" \
    "$project_dir/status.sh" \
    "$project_dir/uninstall.sh" \
    "$project_dir/scripts/install-privileged.sh"; do
    /bin/zsh -n "$script"
done

/bin/zsh "$project_dir/build.sh"
"$project_dir/build/LockPower" --version
"$project_dir/build/LockPower" --self-test

if command -v rg >/dev/null 2>&1; then
    private_matches=$(rg -n 'rexsatonaka|/Volumes/External|CodexProjects' "$project_dir" \
        --glob '!build/**' --glob '!.git/**' --glob '!tests/test.sh' || true)
else
    private_matches=$(/usr/bin/grep -RInE \
        'rexsatonaka|/Volumes/External|CodexProjects' "$project_dir" \
        --exclude-dir=build --exclude-dir=.git --exclude=test.sh || true)
fi

if [[ -n "$private_matches" ]]; then
    echo "$private_matches"
    echo 'Private path or username found in publishable files.' >&2
    exit 1
fi

echo 'All tests passed.'
