#!/usr/bin/env bash
# ============================================================================
#  fighter — one-command "push to GitHub + deploy to the test machine"
#
#  Run this whenever you want to:  commit → push to GH → refresh the game on
#  the remote Mac → validate it loads → launch it for a hands-on test.
#
#  Usage:   bash scripts/deploy.sh      (or just:   push )
#
#  Reads the remote host from ~/.ssh/config as "fighter-dev" (key-based, no
#  password stored anywhere). No secrets live in this repo.
# ============================================================================
set -euo pipefail

REMOTE_HOST="fighter-dev"          # alias defined in ~/.ssh/config
REMOTE_DIR='$HOME/Projects/fighter'
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
LAUNCH_ARGS="${LAUNCH_ARGS:---fullscreen}"   # launch the test window fullscreen

# Run from the project root no matter where you invoke it from.
cd "$(cd "$(dirname "$0")" && pwd)/.."

echo "==> [1/4] Pushing to GitHub (origin/main)..."
git push origin main

echo "==> [2/4] Pulling latest on remote (${REMOTE_HOST})..."
ssh "${REMOTE_HOST}" "cd ${REMOTE_DIR} && git pull --ff-only origin main"

echo "==> [3/4] Importing assets + validating project loads on remote..."
ssh "${REMOTE_HOST}" "cd ${REMOTE_DIR} && ${GODOT} --headless --import --path . > /tmp/fighter_import.log 2>&1; echo 'import finished'; ${GODOT} --headless --path . --quit"

echo "==> [4/4] Launching the game on remote for a test..."
ssh "${REMOTE_HOST}" "cd ${REMOTE_DIR} && (kill \$(cat /tmp/fighter.pid 2>/dev/null) 2>/dev/null || true); nohup ${GODOT} ${LAUNCH_ARGS} --path . > /tmp/fighter_run.log 2>&1 & echo \$! > /tmp/fighter.pid; sleep 4; if kill -0 \$(cat /tmp/fighter.pid) 2>/dev/null; then echo 'GAME LAUNCHED (pid '\$(cat /tmp/fighter.pid)')'; else echo 'game exited early, log:'; cat /tmp/fighter_run.log; fi"

echo "==> Deploy complete. The game should be open on the test machine now."
