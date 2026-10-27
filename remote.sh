#!/bin/bash
# Run one batch on a Windows machine with an NVIDIA GPU (set up there with windows\setup.bat): start
# windows\server.bat over SSH behind a tunnel (here 127.0.0.1:$PORT -> there 127.0.0.1:11439), run the given command
# here with PORT set, then stop the server, also on failure or Ctrl-C.
#   REMOTE_HOST=gpu-box ./remote.sh ./gen.py "a storefront sign that says OPEN 24/7"
#   REMOTE_HOST=gpu-box ./remote.sh bash -c './gen.py "first" && ./gen.py --layout examples/layout.json'
# Settings come from the environment or a git-ignored remote.env beside this script:
#   REMOTE_HOST  SSH host of the GPU machine (an alias from ~/.ssh/config works); key login, no password prompt
#   REMOTE_DIR   the checkout there (default %USERPROFILE%\dev\moss-image-sft)
#   PORT         tunnel port here (default 11440, so a local server.sh can keep 11439)
#   lease_acquire, lease_release  optional shell functions defined in remote.env, run before the server starts and
#                after it stops, e.g. to hold a GPU lock shared with other jobs
set -uo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd -P); cd "$ROOT" || exit 1
[ -f remote.env ] && source remote.env
[ $# -gt 0 ] || { sed -n '2,12p' "$0"; exit 2; }
: "${REMOTE_HOST:?set REMOTE_HOST to the SSH host of the GPU machine}"
REMOTE_DIR=${REMOTE_DIR:-'%USERPROFILE%\dev\moss-image-sft'}
export PORT=${PORT:-11440}
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 "$REMOTE_HOST")

lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t > /dev/null 2>&1 && { echo "Port $PORT is already in use here."; exit 1; }
# A server already on port 11439 there would answer through the tunnel and then be stopped by cleanup.
if "${SSH[@]}" 'cmd /c "netstat -ano | findstr LISTENING | findstr :11439"' > /dev/null 2>&1; then
  echo "Port 11439 is already in use on $REMOTE_HOST; stop that server first."; exit 1
fi
leased=
if declare -F lease_acquire > /dev/null; then
  lease_acquire || { echo "GPU lease not taken."; exit 1; }
  leased=1
fi

tunnel=
cleanup() {
  [ -n "$tunnel" ] && kill "$tunnel" 2> /dev/null && wait "$tunnel" 2> /dev/null
  # Ending the SSH session normally stops the server; make sure before releasing the lease.
  if ! "${SSH[@]}" "cmd /c \"cd /d $REMOTE_DIR && windows\\stop.bat\"" > /dev/null 2>&1; then
    echo "Could not confirm the server stopped on $REMOTE_HOST; check it there."
    [ -n "$leased" ] && echo "The GPU lease is kept until it has."
    return
  fi
  [ -n "$leased" ] && { lease_release || echo "Lease release failed."; }
}
trap cleanup EXIT
trap 'exit 130' INT TERM

"${SSH[@]}" -L "127.0.0.1:$PORT:127.0.0.1:11439" "cmd /c \"cd /d $REMOTE_DIR && windows\\server.bat\"" &
tunnel=$!
for _ in $(seq 1 120); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break
  kill -0 "$tunnel" 2> /dev/null || { echo "Server stopped early; see $REMOTE_DIR\\logs\\sd-server.log there."; exit 1; }
  sleep 2
done
curl -s -o /dev/null "http://127.0.0.1:$PORT/" || { echo "Server did not answer within 4 minutes."; exit 1; }
"$@"
