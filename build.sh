#!/bin/zsh
# Build LidAwake.app into ~/Applications and start it.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/LidAwake.app"
pkill -x LidAwake || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/LidAwake"
cp Info.plist "$APP/Contents/"
codesign --force -s - "$APP"
open "$APP"
