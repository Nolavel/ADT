# There is no C# here, and there never was

**Invariant this belongs to:** `CLAUDE.md` — "Entirely GDScript. Do not introduce C#."

Three claims lived in `CLAUDE.md`'s Project section, in sequence, and all three
were wrong.

**Claim 1: "`tools/scan_folder_files/project_scanner.cs` is the only C# file",
with dropping it recorded as an open backlog item.** That file has never
existed. `git log --all --diff-filter=AD -- '*.cs'` finds nothing in the whole
history, and the path holds `project_scanner.gd`. The backlog item was closed by
never having started.

**Claim 2: the empty `[dotnet] assembly_name="ADT"` block in `project.godot`
came from "someone opening the project once in the .NET editor".** Also wrong,
and in an interesting direction: a screenshot of Stan's editor on 2026-08-28
shows `4.7.stable.mono` in the status bar. The .NET build is not something that
happened once — it is the editor he works in every day. The `[dotnet]` block is
what that editor writes for any project it opens, and says nothing about intent.

**What was true the whole time** is the part that stayed: there is no C# in this
repository, no `.csproj`, no `.sln`, and none should be added.

Corrected 2026-08-27. It was the fourth time a claim in `CLAUDE.md` contradicted
what the repository actually contained — see `documentation_drift.md`.
