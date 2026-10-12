#!/bin/zsh
set -e

password_file="${0:A:h}/.server-root-password"

if [[ ! -r "$password_file" ]]; then
  print -u2 "Не найден файл с паролем: $password_file"
  exit 1
fi

# Встроенный механизм OpenSSH: временный helper передаёт пароль из локального файла.
askpass_script=$(mktemp "${TMPDIR:-/tmp}/ssh-askpass.XXXXXX")
trap 'rm -f "$askpass_script"' EXIT
chmod 700 "$askpass_script"
printf '%s\n' '#!/bin/sh' "IFS= read -r password < '$password_file'" 'printf "%s\n" "$password"' > "$askpass_script"

env DISPLAY="${DISPLAY:-:0}" \
  SSH_ASKPASS_REQUIRE=force \
  SSH_ASKPASS="$askpass_script" \
  ssh root@129.101.115.158
