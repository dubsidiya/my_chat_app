#!/usr/bin/env bash
# Создаёт минимальную ВМ в Yandex Compute Cloud (чтобы потратить грант).
# Требуется: yc установлен и выполнен yc init (или задан token).
set -e

NAME="${1:-chat-server}"
ZONE="${2:-ru-central1-a}"
SUBNET="${3:-default-ru-central1-a}"
# folder-id можно задать через yc config set folder-id <id> или передать 4-м аргументом
FOLDER_ID="${4:-$(yc config get folder-id 2>/dev/null || true)}"

echo "Creating VM: name=$NAME zone=$ZONE subnet=$SUBNET"

if ! command -v yc &>/dev/null; then
  echo "Error: yc not found. Install: brew install --cask yandex-cloud-cli"
  exit 1
fi

if ! yc config list &>/dev/null; then
  echo "Error: yc not authorized. Run: yc init"
  exit 1
fi

if [[ -z "$FOLDER_ID" ]]; then
  echo "Error: folder-id not set. Run: yc config set folder-id <your-folder-id>"
  echo "  Or pass as 4th argument: $0 <name> <zone> <subnet> <folder-id>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init-ssh.yaml"
EXTRA_ARGS=()

# Ключ добавляем через cloud-init (гарантированно срабатывает при первом запуске)
if [[ -f "$CLOUD_INIT" ]]; then
  echo "Using cloud-init to add SSH key on first boot: $CLOUD_INIT"
  EXTRA_ARGS=(--metadata-from-file "user-data=$CLOUD_INIT")
elif [[ -f "$SCRIPT_DIR/.deploy_key.pub" ]]; then
  echo "Using --ssh-key: $SCRIPT_DIR/.deploy_key.pub"
  EXTRA_ARGS=(--ssh-key "$SCRIPT_DIR/.deploy_key.pub")
elif [[ -f "${HOME}/.ssh/id_rsa.pub" ]]; then
  echo "Using --ssh-key: ${HOME}/.ssh/id_rsa.pub"
  EXTRA_ARGS=(--ssh-key "${HOME}/.ssh/id_rsa.pub")
else
  echo "Warning: no cloud-init and no SSH key. ВМ создастся без ключа."
fi

yc compute instance create \
  --folder-id "$FOLDER_ID" \
  --name "$NAME" \
  --zone "$ZONE" \
  --cores 2 \
  --memory 2gb \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,size=15gb \
  --network-interface "subnet-name=$SUBNET,nat-ip-version=ipv4" \
  "${EXTRA_ARGS[@]}"

echo "Done. Get public IP: yc compute instance get $NAME"
