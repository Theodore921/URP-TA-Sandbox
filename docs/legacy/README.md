# Archived: Git + SVN hybrid workflow

These files are kept only for history. They describe how this repository was organised **before**
it became a self-contained open-source project.

## What changed

The project used to split version control in two:

- **Git** — code, shaders, scenes, materials, settings.
- **SVN** — binary art (textures, models, animations, terrain data, screenshots).

That split made sense for a 2.4 GB working copy, but it made the repository **not cloneable on its
own**: a fresh clone opened in Unity showed a pink, asset-less scene until the SVN checkout was
restored.

The art was subsequently committed to Git instead, so everything needed to open the project now
lives in this repository. With the split gone, `VERSION_CONTROL.md` and `Setup-SvnArt.ps1` no
longer describe reality — they are archived here rather than deleted so the reasoning survives.

## Files

| File | Original purpose |
|---|---|
| `VERSION_CONTROL.md` | The full Git/SVN split design: which path went where, lock rules, red lines, migration steps |
| `Setup-SvnArt.ps1` | Bootstrapped/updated the SVN working copy at `Assets/` right after cloning |

## Do not follow them

Nothing here is part of the build or the editing workflow. In particular `Setup-SvnArt.ps1`
clones an SVN repository that no longer backs this project.

See the root [README](../../README.md) for the current setup.
