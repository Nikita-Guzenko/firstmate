# Nikita's fork

Fork of [kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) with two intentional deviations, both confined to the top of `AGENTS.md`:

1. **Plain tone, address by name.** No "captain", no nautical flavor. The word "captain" elsewhere in AGENTS.md is an internal role term meaning Nikita.
2. **One home per project.** Each project gets its own independent firstmate home (own clone, state, lock, `projects/`). Firstmate must never suggest consolidating projects under one home.

## New project setup

```sh
git clone https://github.com/Nikita-Guzenko/firstmate ~/fm/<project>
cd ~/fm/<project> && claude   # register only that project
```

## Syncing with upstream

Run from any clone (or ask the agent to):

```sh
git fetch upstream                # upstream = kunchenguid/firstmate
git merge upstream/main           # conflicts only if upstream edits the patched top block
git push origin main              # origin = this fork
```

Merge commits (not rebase) keep every local home fast-forwardable, so `/updatefirstmate` keeps working: it FF-pulls from `origin` = this fork.

In a fresh clone add the upstream remote once: `git remote add upstream https://github.com/kunchenguid/firstmate`.
