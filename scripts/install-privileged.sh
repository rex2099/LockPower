#!/bin/zsh
set -euo pipefail

source_file=${1:?Missing sudoers source file}
target_file='/etc/sudoers.d/lockpower'

if [[ ! -f "$source_file" ]]; then
    echo 'Sudoers source file not found.' >&2
    exit 1
fi

/usr/sbin/visudo -cf "$source_file"
/usr/bin/install -o root -g wheel -m 0440 "$source_file" "$target_file"
/usr/sbin/visudo -cf "$target_file"
