#!/bin/bash
# Demo helper for filming Pasteboard.
#
#   ./Video/demo.sh setup     swap in demo notes, relaunch the app, load demo clips
#   ./Video/demo.sh clips     just reload the demo clips (after "Clear History")
#   ./Video/demo.sh assets    regenerate the demo images/file in Video/assets
#   ./Video/demo.sh restore   put your real notes back and relaunch the app
#
# Your real notes are backed up to notes.real-backup.json before anything is changed,
# and "setup" refuses to run twice so the backup can never be overwritten by demo data.
set -e
cd "$(dirname "$0")/.."

TOOL=/tmp/pasteboard_demo_tool
DIR="$HOME/Library/Application Support/Pasteboard"
NOTES="$DIR/notes.json"
BACKUP="$DIR/notes.real-backup.json"
APP=/Applications/Pasteboard.app

build_tool() {
    swiftc -O -o "$TOOL" OmniClip/NoteModels.swift Video/main.swift
}
quit_app()   { pkill -f "Pasteboard.app/Contents/MacOS/Pasteboard" 2>/dev/null || true; sleep 1; }
# wait until the app is fully up — it only sees clipboard changes made after it starts
launch_app() { open "$APP"; sleep 5; }

case "$1" in
  setup)
    if [ -e "$BACKUP" ]; then
      echo "A backup already exists ($BACKUP) — demo data is probably already active."
      echo "Run './Video/demo.sh restore' first."; exit 1
    fi
    build_tool
    quit_app
    [ -e "$NOTES" ] && cp "$NOTES" "$BACKUP" || echo "[]" > "$BACKUP"
    "$TOOL" notes "$NOTES"
    launch_app
    "$TOOL" clips
    echo "Demo ready. When you're done: ./Video/demo.sh restore"
    ;;
  clips)
    build_tool; "$TOOL" clips ;;
  assets)
    build_tool; "$TOOL" assets Video/assets ;;
  restore)
    if [ ! -e "$BACKUP" ]; then echo "No backup found — nothing to restore."; exit 1; fi
    quit_app
    mv "$BACKUP" "$NOTES"
    launch_app
    echo "Your real notes are back."
    ;;
  *)
    sed -n '2,10p' "$0"; exit 1 ;;
esac
