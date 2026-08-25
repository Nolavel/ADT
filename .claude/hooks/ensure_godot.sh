#!/bin/sh
# Makes the Godot CLI available to an agent session.
#
# WHY: agent sessions on claude.ai/code run in a fresh, throwaway container
# that has no Godot. Without it an agent can only read and cross-reference
# GDScript — it cannot answer "does this parse", "does the project still
# open", or "does the player land on the ground". With it, all three are one
# command each. See docs/ENTIRE_SETUP.md's sibling section in CLAUDE.md.
#
# Does nothing when godot is already on PATH, so this is inert on a developer
# machine and only pays the download in a container that lacks it.
#
# Deliberately does NOT import the project: the first `godot --headless
# --editor --quit` does that on demand, takes minutes on this repo, and would
# block session start for no reason if the session never touches the engine.
set -e

if command -v godot >/dev/null 2>&1; then
	exit 0
fi

VERSION="4.7.2"
BIN="/opt/godot/Godot_v${VERSION}-stable_linux.x86_64"

if [ ! -x "$BIN" ]; then
	# The GitHub Releases HTML page is blocked by the agent proxy, but the
	# redirect through downloads.godotengine.org to the release-asset CDN is
	# allowed. Fetch through the official domain, not github.com directly.
	URL="https://downloads.godotengine.org/?version=${VERSION}&flavor=stable&slug=linux.x86_64.zip"
	mkdir -p /opt/godot
	curl -sS -L --max-time 600 -o /opt/godot/godot.zip "$URL" || exit 0
	unzip -o -q /opt/godot/godot.zip -d /opt/godot || exit 0
	rm -f /opt/godot/godot.zip
	chmod +x "$BIN" || exit 0
fi

ln -sf "$BIN" /usr/local/bin/godot 2>/dev/null || exit 0
