#!/bin/sh
set -eu
IMAGE="${1:-miabi/sync:test}"
ID="smoke-$$"
NET="$ID-net"; SRC="$ID-src"; DST="$ID-dst"; DAEMON="$ID-d"
SECRET="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

cleanup() {
  docker rm -f "$DAEMON" >/dev/null 2>&1 || true
  docker volume rm -f "$SRC" "$DST" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create --internal "$NET" >/dev/null
docker volume create "$SRC" >/dev/null
docker volume create "$DST" >/dev/null
docker run --rm -v "$SRC:/data" "$IMAGE" sh -c \
  'mkdir -p /data/a/b && head -c 2000000 /dev/urandom > /data/a/big && echo hi > /data/a/b/small && ln -s b/small /data/a/link && chown 1234:5678 /data/a/b/small'

docker run -d --name "$DAEMON" --network "$NET" -e SYNC_SECRET="$SECRET" -v "$SRC:/data:ro" "$IMAGE" sh -c '
  set -e; umask 077
  printf "mb:%s\n" "$SYNC_SECRET" > /tmp/rsyncd.secrets
  printf "%s\n" "uid = 0" "gid = 0" "use chroot = no" "[data]" "path = /data" "read only = yes" \
    "auth users = mb" "secrets file = /tmp/rsyncd.secrets" > /tmp/rsyncd.conf
  exec rsync --daemon --no-detach --port=873 --config=/tmp/rsyncd.conf' >/dev/null

for i in 1 2 3 4 5 6 7 8 9 10; do
  if docker run --rm --network "$NET" -e RSYNC_PASSWORD="$SECRET" -v "$DST:/data" "$IMAGE" \
      rsync -aH --numeric-ids --delete "rsync://mb@$DAEMON:873/data/" /data/; then
    break
  fi
  [ "$i" = 10 ] && { echo "rsync never succeeded" >&2; exit 1; }
  sleep 1
done

sum='cd /data && find . | sort | while read -r f; do stat -c "%n %s %u:%g %F" "$f"; [ -f "$f" ] && [ ! -L "$f" ] && md5sum "$f"; done; true'
a="$(docker run --rm -v "$SRC:/data" "$IMAGE" sh -c "$sum")"
b="$(docker run --rm -v "$DST:/data" "$IMAGE" sh -c "$sum")"
if [ "$a" != "$b" ]; then
  printf 'copy differs\nsource:\n%s\ntarget:\n%s\n' "$a" "$b" >&2
  exit 1
fi
echo "ok: target matches source"
