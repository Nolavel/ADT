# Why `*.import` files are committed

**Invariant this belongs to:** `CLAUDE.md`, Style conventions — "`*.import`
files are committed; `.godot/` is not."

Godot 4 stores an imported asset's UID **inside its `.import` file**. Ignoring
those files means every fresh clone mints its own UIDs on first import, while
the `.tscn` files referencing those assets still carry whoever-committed-them's.

The symptom: a fresh clone of this repository used to open with **28 `invalid
UID` warnings** and a project font that failed to load.

This is Godot's own recommended layout, not a workaround. `.gitignore` says so
at the line where it used to ignore them.
