#!/usr/bin/env python3
"""Fails when a .gd file is referenced by nothing.

WHY THIS EXISTS. Godot's import pass compiles a script only when something
reaches it. A .gd that no scene, resource, autoload or other script names is
never parsed, so a syntax error inside it passes CI green. CLAUDE.md documents
that gap; this closes it.
    -> docs/postmortems/orphan_scripts.md

WHAT COUNTS AS A REFERENCE. A script can be named three different ways and all
three are checked, because using only one produces false alarms:
  * by path      "res://npc/npc_base.gd"     - .tscn ExtResource, preload, load
  * by uid       "uid://bxxxx"               - what Godot actually writes into
                                               .tscn/.tres after an import
  * by class_name  NPCBase                   - a global class needs no path at
                                               all, which is how most gameplay
                                               scripts reach each other here

DELIBERATELY BIASED TOWARD SILENCE. class_name matching is by word, so a bare
mention in a comment counts as a reference. That direction is chosen: a
detector that fails CI on a live file gets switched off within a week, and is
then worse than no detector at all. Missing one orphan costs a follow-up; a
false alarm costs the whole check.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Directories whose scripts are not ours to police. addons/ is third-party or
# editor-plugin code with its own entry points (plugin.cfg), and .godot/ is
# generated.
SKIP_DIRS = {".git", ".godot", "addons"}

# Files that are entry points by nature rather than by reference. Each line
# needs its own reason — a blanket tools/** glob would silence the very files
# most likely to rot, so this stays an explicit list.
ALLOWED_ORPHANS = {
    # --- EditorScripts: run by hand with File -> Run, no caller by design. ---
    # Each is the only reproducible path to a piece of committed content, which
    # is why they are kept rather than deleted after use.
    "tools/block_generator/block_library_generator.gd",   # bakes the block library
    "tools/block_generator/block_placer.gd",              # places blocks from world data
    "tools/block_generator/feature_test_block.gd",        # builds the feature test block
    "tools/block_generator/test_block_builder.gd",        # builds the test block
    "tools/block_generator/tower_builder.gd",             # builds a tower block
    "tools/build_aogashima_terrain/build_aogashima_terrain.gd",  # bakes the island mesh
    "tools/city_generator/generate_city.gd",              # generates the city layout
    "tools/island_generator/aogashima_generator.gd",      # generates the island
    # --- A SceneTree script, run with `godot --script`, same situation. ---
    "tools/city_generator/generate_city_cli.gd",          # the CLI half of generate_city
    # --- Open, not settled. ---
    # A Resource schema with class_name MapData and neither producer nor
    # consumer. It sits in core/map_source/, the level-design tool set CLAUDE.md
    # marks do-not-refactor, so deleting it is not this check's call to make.
    # Whether it gets wired or dropped is a question for Stan — docs/NOW.md.
    "core/map_source/map_data.gd",
}

# Anything that can name a script.
SCANNED_SUFFIXES = (".gd", ".tscn", ".tres", ".cfg", ".godot", ".import")


def collect_scripts():
    """Every .gd we are responsible for, with the three names it can go by."""
    scripts = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if not name.endswith(".gd"):
                continue
            abs_path = os.path.join(dirpath, name)
            rel = os.path.relpath(abs_path, ROOT).replace(os.sep, "/")
            scripts[rel] = {
                "res": "res://" + rel,
                "uid": read_uid(abs_path + ".uid"),
                "class_name": read_class_name(abs_path),
            }
    return scripts


def read_uid(uid_path):
    if not os.path.isfile(uid_path):
        return None
    with open(uid_path, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read().strip()
    return text if text.startswith("uid://") else None


def read_class_name(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = re.match(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", line)
            if match:
                return match.group(1)
    return None


def collect_corpus():
    """Every file that could name a script, as (relative path, text)."""
    corpus = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if not name.endswith(SCANNED_SUFFIXES) and name != "project.godot":
                continue
            abs_path = os.path.join(dirpath, name)
            rel = os.path.relpath(abs_path, ROOT).replace(os.sep, "/")
            try:
                with open(abs_path, "r", encoding="utf-8", errors="replace") as handle:
                    corpus.append((rel, handle.read()))
            except OSError:
                continue
    return corpus


def is_referenced(rel, names, corpus):
    """True when some OTHER file names this script by path, uid or class_name."""
    class_pattern = None
    if names["class_name"]:
        class_pattern = re.compile(r"\b%s\b" % re.escape(names["class_name"]))

    for other_rel, text in corpus:
        # A script naming itself proves nothing, and neither does its own .uid.
        if other_rel == rel or other_rel == rel + ".uid":
            continue
        if names["res"] in text:
            return True
        if names["uid"] and names["uid"] in text:
            return True
        if class_pattern and class_pattern.search(text):
            return True
    return False


def main():
    scripts = collect_scripts()
    corpus = collect_corpus()

    orphans = [
        rel
        for rel, names in sorted(scripts.items())
        if rel not in ALLOWED_ORPHANS and not is_referenced(rel, names, corpus)
    ]

    print("scanned %d scripts, %d allowed entry points" % (len(scripts), len(ALLOWED_ORPHANS)))
    if not orphans:
        print("no orphans")
        return 0

    print("")
    print("These .gd files are referenced by nothing — no scene, resource,")
    print("autoload or other script names them by path, uid or class_name.")
    print("Godot never compiles them, so a syntax error inside one passes CI:")
    for rel in orphans:
        print("  %s" % rel)
    print("")
    print("Wire it to something, delete it, or add it to ALLOWED_ORPHANS in")
    print("%s with a reason on its own line." % os.path.relpath(__file__, ROOT))
    return 1


if __name__ == "__main__":
    sys.exit(main())
