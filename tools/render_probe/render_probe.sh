#!/bin/sh
# Renders the game and leaves PNG frames on disk, so a change can be LOOKED AT
# instead of argued about from logs.
#
# WHY THIS EXISTS. The verification ladder in CLAUDE.md runs headless, and
# headless is the dummy driver: it never compiles a shader and never calls
# _draw(). Every visual defect is therefore invisible to it — which is how a
# diverging spring in dynamic_cursor_ui.gd printed 7714 warnings in a live
# session while every headless check stayed silent and green. Reported by
# Stan, 2026-08-28.
#
# WHAT IT PROVES AND WHAT IT DOES NOT. This runs the COMPATIBILITY renderer on
# software OpenGL (no GPU in an agent container, and no software Vulkan
# either — /usr/share/vulkan/icd.d is empty). The project ships Forward+, so:
#
#   trustworthy   geometry, silhouette, placement, orientation, UI layout,
#                 whether a widget draws at all, whether text fits
#   NOT           lighting, shadows, fog, SSIL/SSR, post-processing, and any
#                 material whose look depends on them
#
# So it answers "is the rifle across the hands" and "is the ring under the
# feet", never "does the noir look right". Say which of the two a screenshot
# is being used for.
#
# Frames come from Godot's own --write-movie, which writes a PNG sequence.
# No ffmpeg, xwd or ImageMagick in the container, and none needed.
#
# Usage:  sh tools/render_probe/render_probe.sh [frames] [out_dir] [scene]
# Default: 120 frames into a temp directory, path printed at the end.
set -e

FRAMES="${1:-120}"
OUT_DIR="${2:-$(mktemp -d)}"
SCENE="${3:-}"
FPS=20

if ! command -v xvfb-run >/dev/null 2>&1; then
	echo "render_probe: xvfb-run is not installed; cannot open a display" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"

# --fixed-fps decouples the simulation from how slowly software GL actually
# draws, so frame N is always the same moment of game time no matter how long
# the machine took to get there. That is what makes two screenshots
# comparable across runs.
if [ -n "$SCENE" ]; then
	xvfb-run -a -s "-screen 0 1280x720x24" \
		godot --display-driver x11 --rendering-driver opengl3 \
		--resolution 1280x720 \
		--fixed-fps "$FPS" \
		--write-movie "$OUT_DIR/frame.png" \
		--quit-after "$FRAMES" \
		"$SCENE" \
		> "$OUT_DIR/render.log" 2>&1 || true
else
	xvfb-run -a -s "-screen 0 1280x720x24" \
		godot --display-driver x11 --rendering-driver opengl3 \
		--resolution 1280x720 \
		--fixed-fps "$FPS" \
		--write-movie "$OUT_DIR/frame.png" \
		--quit-after "$FRAMES" \
		> "$OUT_DIR/render.log" 2>&1 || true
fi

LAST=$(ls "$OUT_DIR"/frame*.png 2>/dev/null | tail -n 1)
if [ -z "$LAST" ]; then
	echo "render_probe: no frames were written — see $OUT_DIR/render.log" >&2
	exit 1
fi

echo "frames:    $(ls "$OUT_DIR"/frame*.png | wc -l)"
echo "last:      $LAST"
echo "log:       $OUT_DIR/render.log"
echo "warnings:  $(grep -c 'WARNING' "$OUT_DIR/render.log" || true)"
echo "errors:    $(grep -c 'ERROR' "$OUT_DIR/render.log" || true)"
