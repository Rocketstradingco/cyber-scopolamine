# RTCO Local Agent

A local AI coding agent for Windows. It runs a code model **entirely on your own
GPU** — no API keys, no accounts, no cloud, no per-token cost, and it keeps
working with the network unplugged.

One command installs everything and sets it up for your specific graphics card.

```powershell
irm https://raw.githubusercontent.com/REPLACE-ME/rtco-local-agent/main/install.ps1 | iex
```

Then double-click **RTCO Local Agent (Sandbox)** on your Desktop.

---

## What this actually is

Two separate programs, and it helps a lot to know which is which:

| | **aider** | **Ollama** |
|---|---|---|
| Role | The CLI you talk to | The engine that runs the model |
| Does | Reads your repo, decides which files matter, writes the prompt, applies edits to real files, handles git | Loads model weights onto your GPU and generates text |
| Knows about | Your code | Nothing about your code |
| Runs on | CPU, negligible resources | **Your GPU** |

**aider is the driver, Ollama is the engine.** aider has no model of its own; it
sends prompts to Ollama and applies whatever comes back. If Ollama isn't
running, aider has nothing to talk to — that's the single most common
confusion, and the launcher starts Ollama for you to avoid it.

## What gets installed

Everything is **per-user — no administrator rights needed.**

| Component | Where |
|---|---|
| Ollama (model engine) | `%LOCALAPPDATA%\Programs\Ollama` |
| uv (Python tool manager) | `~\.local\bin` |
| aider **0.86.2** (pinned — see below) | `~\.local\bin\aider.exe` |
| The model (several GB) | your fastest drive, e.g. `C:\ollama\models` |
| RTCO customizations | `~\.config\rtco` |
| `rtco-*` commands | `~\.local\bin` (added to your PATH) |
| Sandbox workspace | e.g. `C:\rtco-sandbox` |
| Desktop shortcut | your Desktop |

## The sandbox

The agent is pointed at **one folder** (`C:\rtco-sandbox` by default) and works
there. Put a project in it, or let the agent create files in it. This is a
guardrail, not a prison — it keeps a small local model from wandering into the
rest of your disk on a vague instruction.

**Auto-commit is deliberately off.** These models are much weaker than Claude or
GPT, so their edits are reviewed by you before they become git history. Run
`git diff` and commit yourself.

## Which model you get

The installer reads your GPU's VRAM and picks a model that **actually fits**:

| VRAM | Model | Context |
|---|---|---|
| 20 GB+ | `qwen2.5-coder-abliterate:14b` | 32K |
| 10–20 GB | `qwen2.5-coder-abliterate:7b` | 32K |
| 7–10 GB | `qwen2.5-coder-abliterate:7b` | 16K |
| 5–7 GB | `qwen2.5-coder-abliterate:3b` | 16K |
| under 5 GB | `qwen2.5-coder-abliterate:3b` | 8K (slow, CPU) |

This matters more than it sounds. **A model larger than your VRAM does not
produce an error** — Ollama silently moves the overflow into system RAM and
generation gets roughly 5× slower. It just feels broken. So the installer errs
on the small side.

The model is *abliterated*, meaning refusal behaviour has been removed. It will
attempt anything you ask. It is also small: expect it to be confidently wrong
sometimes. Review its output.

### Context size, and why it's bigger than default

Stock Ollama gives a model a small context window. aider needs far more than
that — its repo map alone is budgeted at 4096 tokens before any of your actual
code is added, and small models use *whole-file* edits, meaning the entire file
goes up **and** comes back. So the installer builds an `-agent` variant of the
model: identical weights, larger `num_ctx`.

Context costs VRAM (roughly 56 KB per token for a 7b), which is why it's sized
to your card.

## Using it

Double-click the Desktop icon. You land in the sandbox with aider running.

| Command | What |
|---|---|
| `rtco-sandbox-aider` | Start the agent (same as the icon) |
| `rtco-aider-history list` | List archived conversations |
| `rtco-aider-history view 1` | Read one |
| `rtco-aider-history load 1` | Restore one as the active chat |
| `rtco-status` (or `rtco`) | Machine + model status |
| `rtco-aider-patch` | Re-apply the RTCO aider patches |
| `rtco-ollama-noupdate` | Re-disable Ollama's auto-updater |

Inside aider: `/add <file>` to put a file in context, `/model <alias>` to swap
models, `/help` for everything, `Ctrl-C` twice to quit.

**Every launch starts with a fresh conversation.** The previous one is archived,
not deleted — small models get confused by long histories, so context doesn't
bleed between sessions. Use `rtco-aider-history` to bring one back.

## What's customized

- **Themed shell** — RTCO prompt with git branch/dirty state, running jobs, and
  exit-code marker, plus `rtco-status`
- **Startup banner** — model, honest scope guidance, and a live tokens/sec
  reading, with a spinner while the model loads into VRAM
- **Cyberpunk waiting animation** — aider's "Waiting for `<model>`" is replaced
  with 76 rotating glitchy neon phrases
- **Fixed `/model` picker** — stock aider offers ~3000 *cloud* model names from
  litellm on Tab-complete, useless on an offline box. Now it offers only your
  local models
- **Chat-history archiving** — see above
- **Orphan reaper** — see troubleshooting

## Troubleshooting

### It's suddenly 5× slower

Almost always **orphaned model runners eating VRAM**. Ollama runs each model in
a child `llama-server.exe`; if Ollama is force-killed or crashes, those children
survive *and keep their full VRAM allocation*. The next model then can't fit and
spills to system RAM.

The launcher reaps them automatically at startup, so the fix is usually to close
the window and relaunch from the icon. To check by hand:

```powershell
(Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage').CounterSamples |
    ForEach-Object { [math]::Round($_.CookedValue/1MB) }   # MB of VRAM in use
Get-Process llama-server, ollama
```

**Warning:** `ollama ps` reports `100% GPU` even while it is spilling to system
RAM. It is not a reliable check. Trust the VRAM counter instead.

### The spinner/animation is missing

The animation needs a real console. Launch from the Desktop icon or a normal
terminal, not from a script or IDE task runner.

### `ollama` commands crash instantly

Ollama **0.23.x** on Windows crashes at startup on AMD cards — its image-gen
module is built CUDA-only but initializes unconditionally, so it access-violates
before any command runs, `serve` included. Install 0.32.6 or newer. The
installer enforces this.

### After upgrading aider, the customizations vanished

Expected. The patches edit aider's **installed** package, so
`uv tool upgrade aider-chat` wipes them. Run `rtco-aider-patch`.

This is also why aider is **pinned to 0.86.2** — the patches are diffs against
that exact release and may not apply to a newer one.

### Ollama updated itself and broke

Run `rtco-ollama-noupdate`. Ollama has no supported setting for this, so the
tool renames the tray app (which *is* the updater) and write-protects its update
staging folder. `ollama serve` runs the API fine without the tray icon. Re-run
after any manual Ollama install, which restores it.

## What this is good at, and what it isn't

**Good at:** small well-scoped edits, one or a few files, boilerplate, tests,
refactoring a single function, explaining code, working offline, and anything
you'd rather not send to a third party.

**Bad at:** large multi-file refactors, ambiguous instructions, subtle
architecture decisions, and long conversations. A 7b model is a fraction of the
size of a frontier model. For heavy work, reach for Claude Code or Codex — this
is for the offline, private, zero-cost middle ground.

## Uninstalling

```powershell
# remove the tooling
uv tool uninstall aider-chat
Remove-Item -Recurse ~\.config\rtco, ~\.local\bin\rtco-*
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\RTCO Local Agent (Sandbox).lnk"

# the model store and sandbox (check the sandbox for work you want first)
Remove-Item -Recurse C:\ollama\models, C:\rtco-sandbox
```

Uninstall Ollama from Windows Settings → Apps.
