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

SSH_KEY="${HOME}/.ssh/id_rsa.pub"
if [[ ! -f "$SSH_KEY" ]]; then
  echo "Warning: $SSH_KEY not found. SSH key will not be added (use console or set --metadata-from-file)."
  SSH_ARGS=()
else
  SSH_ARGS=(--ssh-key "$SSH_KEY")
fi

yc compute instance create \
  --folder-id "$FOLDER_ID" \
  --name "$NAME" \
  --zone "$ZONE" \
  --cores 2 \
  --memory 2gb \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,size=15gb \
  --network-interface "subnet-name=$SUBNET,nat-ip-version=ipv4" \
  "${SSH_ARGS[@]}"

echo "Done. Get public IP: yc compute instance get $NAME"
