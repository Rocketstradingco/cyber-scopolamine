```
 ██████╗██╗   ██╗██████╗ ███████╗██████╗
██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗
██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝
██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗
╚██████╗   ██║   ██████╔╝███████╗██║  ██║
 ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝
███████╗ ██████╗ ██████╗ ██████╗  ██████╗ ██╗      █████╗ ███╗   ███╗██╗███╗   ██╗███████╗
██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔═══██╗██║     ██╔══██╗████╗ ████║██║████╗  ██║██╔════╝
███████╗██║     ██║   ██║██████╔╝██║   ██║██║     ███████║██╔████╔██║██║██╔██╗ ██║█████╗
╚════██║██║     ██║   ██║██╔═══╝ ██║   ██║██║     ██╔══██║██║╚██╔╝██║██║██║╚██╗██║██╔══╝
███████║╚██████╗╚██████╔╝██║     ╚██████╔╝███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║███████╗
╚══════╝ ╚═════╝ ╚═════╝ ╚═╝      ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝
C17H21NO4  //  DEVIL'S BREATH FOR YOUR CODEBASE  //  IT CANNOT REFUSE
```

**An RTCO Labs project.**

A local AI coding agent for Windows. It runs an *abliterated* code model —
refusal behaviour removed — **entirely on your own GPU**. No API keys, no
account, no cloud, no per-token cost, and it keeps working with the network
unplugged.

Installs everything and tunes it to your specific graphics card.

1. Get the whole folder — **Code → Download ZIP** here, or the ZIP you were
   sent
2. Right-click the ZIP → **Extract All**
3. Open the extracted `cyber-scopolamine` folder
4. Double-click **`Install Cyber-Scopolamine.bat`**

Windows will likely show *"Windows protected your PC"* because the file came
from the internet — click **More info → Run anyway**. The installer is a plain
text script; you can read every line of `install.ps1` first.

`INSTALL.txt` in the same folder covers all of this in plain language, plus
first steps and troubleshooting.

> **This repository is private**, so there is no `irm … | iex` one-liner and no
> public download link. `install.ps1` must be run from an extracted copy of the
> folder — it needs the `config\`, `bin\` and `patches\` directories sitting
> next to it. Run on its own, it stops and says so rather than failing with a
> 404.

When it finishes, double-click **Cyber-Scopolamine** on your Desktop. The first
launch plays a short intro explaining what this is; it plays once, and
`cyber-scopolamine-intro` replays it.

---

## What it actually is

Two programs, and knowing which is which saves a lot of confusion:

| | **aider** | **Ollama** |
|---|---|---|
| Role | The CLI you talk to | The engine that runs the model |
| Does | Reads your code, decides which files matter, writes the prompt, applies edits to real files, handles git | Loads model weights onto your GPU and generates text |
| Knows about | Your code | Nothing about your code |
| Runs on | CPU, negligible resources | **Your GPU** |

**aider is the driver, Ollama is the engine.** aider has no model of its own —
it sends prompts to Ollama and applies what comes back. If Ollama isn't
running, aider has nothing to talk to. The launcher starts it for you.

## Requirements

- Windows 10 or 11
- A GPU with **4 GB VRAM or more** (NVIDIA, AMD, or Intel). Less works, on CPU,
  slowly.
- ~30 GB free disk
- **No administrator rights.** Everything installs per-user.

Optional but recommended: **Git for Windows** (the sandbox becomes a real repo,
and its bundled `patch.exe` enables the themed spinner) and **PowerShell 7**
(renders the theme properly).

## What gets installed

| Component | Where |
|---|---|
| Ollama (model engine) | `%LOCALAPPDATA%\Programs\Ollama` |
| uv (Python tool manager) | `~\.local\bin` |
| aider **0.86.2**, pinned | `~\.local\bin\aider.exe` |
| The model (several GB) | your fastest drive |
| Customizations | `~\.config\cyber-scopolamine` |
| `cyber-scopolamine*` commands | `~\.local\bin` (added to PATH) |
| Sandbox workspace | your fastest drive |
| Desktop shortcut | your Desktop |

The installer scans first and reports what you already have, so re-running it is
safe — it skips anything already present.

## The sandbox

The agent is pointed at **one folder** and works only there. Put a project in
it, or let the agent create files. It's a guardrail, not a prison — it stops a
small local model from wandering across your disk on a vague instruction.

**Auto-commit is deliberately off.** These models are far weaker than Claude or
GPT, so you review their edits before they become git history. Run `git diff`
and commit yourself.

## Which model you get

The installer reads your VRAM and picks a model that **actually fits**:

| VRAM | Model | Context |
|---|---|---|
| 20 GB+ | `qwen2.5-coder-abliterate:14b` | 32K |
| 10–20 GB | `qwen2.5-coder-abliterate:7b` | 32K |
| 7–10 GB | `qwen2.5-coder-abliterate:7b` | 16K |
| 5–7 GB | `qwen2.5-coder-abliterate:3b` | 16K |
| under 5 GB | `qwen2.5-coder-abliterate:3b` | 8K (CPU, slow) |

This matters more than it sounds. **A model larger than your VRAM does not
error** — Ollama silently moves the overflow into system RAM and generation gets
roughly 5× slower. It just feels broken. So the sizing errs small.

Both the model store and the sandbox go on your **fastest drive** by default.
Disk class dominates start-up time: the same 7b model loads in about **9
seconds from an NVMe SSD versus 57 seconds from a spinning HDD**. The installer
ranks NVMe above SATA SSD above HDD and ignores a small free-space advantage on
a slower disk.

### Why the context is enlarged

Stock Ollama gives models a small context window. aider needs much more — its
repo map alone is budgeted at 4096 tokens before any of your code, and small
models use *whole-file* edits, meaning the entire file goes up **and** comes
back. So the installer builds a local variant (`cyscop-7b`, `cyscop-3b`) with a
larger `num_ctx`: identical weights, more room. Context costs VRAM, which is why
it's sized to your card.

## Using it

Double-click the icon. You land in the sandbox with the agent running.

| Command | What |
|---|---|
| `cyber-scopolamine` | Start the agent (same as the icon) |
| `cyber-scopolamine-chat` | Start in conversation mode — talk, no file edits |
| `cyber-scopolamine-history list` | List archived conversations |
| `cyber-scopolamine-history view 1` | Read one |
| `cyber-scopolamine-history load 1` | Restore one as the active chat |
| `scop` | Status: GPU, VRAM in use, loaded model, sandbox |
| `cyber-scopolamine-intro` | Replay the intro sequence |
| `cyber-scopolamine-patch` | Re-apply the themed aider patches |
| `cyber-scopolamine-noupdate` | Explicitly disable Ollama's auto-updater |
| `cyber-scopolamine-noupdate -Undo` | Restore updater state changed by this project |

Inside aider: `/add <file>` puts a file in context, `/model <alias>` swaps
models, `/help` lists everything, `Ctrl-C` twice quits.

### It's an editor, not a chatbot

This trips everyone up first time. `cyber-scopolamine` starts in **code mode**,
where every message is treated as a request to change code — say "hello" and it
will ask what you want edited. That's by design: it's a coding agent.

**If you want to just talk, use a different command:**

```powershell
cyber-scopolamine-chat
```

That's a plain conversation with the same local model — streamed, with memory
of the conversation, and no repo attached at all. It cannot read or write
files, so it can't touch anything. Commands inside it: `/exit`, `/clear`,
`/model <name>`, `/save <file>`.

Inside the editor you can also switch modes without leaving:

| | |
|---|---|
| `/ask <question>` | Ask one question, no edits |
| `/ask` | Switch to asking about the code |
| `/code` | Switch back to editing |

Note that aider's `--chat-mode` flag is **not** a chat mode — it's an alias for
`--edit-format`, so passing it a made-up value just prints a list of edit
formats. Use `cyber-scopolamine-chat` or `/ask`.

**Every launch starts a fresh conversation.** The previous one is archived, not
deleted — small models get confused by long histories, so context doesn't bleed
between sessions. `cyber-scopolamine-history` brings one back.

## What's customized

- **Launch banner** and a themed prompt with git branch/dirty state, running
  jobs and an exit-code marker
- **Startup readout** — model, honest scope guidance, and a live tokens/sec
  measurement, with a spinner while the model loads into VRAM
- **Themed waiting animation** — aider's "Waiting for `<model>`" replaced with
  76 rotating glitched phrases
- **Fixed `/model` picker** — stock aider Tab-completes ~3000 *cloud* model
  names from litellm, useless offline. Now it offers only your local models
- **Chat-history archiving** — see above
- **Orphan reaper** — see below

## Troubleshooting

### It suddenly got ~5× slower

Almost always **orphaned model runners eating VRAM**. Ollama runs each model in
a child `llama-server.exe`; if Ollama is force-killed or crashes, those children
survive *and keep their full VRAM allocation*. The next model then can't fit and
spills into system RAM.

The launcher reaps them at startup, so closing the window and relaunching from
the icon usually fixes it. `scop` warns when it detects them. To check by hand:

```powershell
(Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage').CounterSamples |
    ForEach-Object { [math]::Round($_.CookedValue/1MB) }
Get-Process llama-server, ollama
```

**Warning:** `ollama ps` reports `100% GPU` even while spilling into system RAM.
It is not a reliable check — trust the VRAM counter.

### The animation doesn't show

It needs a real console. Launch from the Desktop icon or a normal terminal, not
from a script or an IDE task runner.

### `ollama` crashes instantly

Ollama **0.23.x** on Windows crashes at startup on AMD cards: its image-gen
module is built CUDA-only but initializes unconditionally, so it access-violates
before any command runs, `serve` included. Install 0.32.6 or newer — the
installer enforces this.

### The customizations vanished after upgrading aider

Expected. The patches edit aider's **installed** package, so
`uv tool upgrade aider-chat` wipes them. Run `cyber-scopolamine-patch`.

That's also why aider is **pinned to 0.86.2** — the patches are diffs against
that exact release.

### Ollama updated itself and broke

Run `cyber-scopolamine-noupdate`. Ollama has no supported setting for this, so
the tool renames the tray app (which *is* the updater) and write-protects its
update staging folder. `ollama serve` runs the API fine without the tray icon.
Re-run after any manual Ollama install, which restores it.

## What it's good at, and what it isn't

**Good at:** small well-scoped edits, one or a few files, boilerplate, tests,
refactoring a single function, explaining code, working offline, and anything
you'd rather not send to a third party.

**Bad at:** large multi-file refactors, ambiguous instructions, subtle
architecture decisions, long conversations. A 7b model is a fraction of the size
of a frontier model, and it will be confidently wrong sometimes. Review its
output. For heavy work reach for Claude Code or Codex — this is for the
offline, private, zero-cost middle ground.

The model is abliterated, meaning it will attempt whatever you ask. That is the
point of the name. What you do with it is on you.

## It shares, it doesn't take over

If you already use Ollama or aider, this installs **alongside** them:

- **Your Ollama model store is detected and shared**, never replaced — so
  nothing is downloaded twice and your existing models keep working. The agent
  uses a dedicated localhost endpoint (port `11435` by default) and records the
  exact process it starts; it never stops Ollama processes merely by name.
- **aider is installed into a private environment** of its own
  (`~\.config\cyber-scopolamine\aider-env`). Your own aider is never touched,
  downgraded, or patched. That matters because this build is pinned to one
  exact release and the themed patches rewrite aider's package internals —
  doing that to a shared install would change how aider behaves in all your
  other work.

## Uninstalling

Double-click **`Uninstall Cyber-Scopolamine.bat`**, or run:

```powershell
cyber-scopolamine-uninstall          # add -DryRun to preview
```

It removes the commands, the config folder, the private aider environment and
the desktop shortcut. If you explicitly disabled Ollama auto-update through the
installer or helper command, uninstall restores the recorded tray-app and ACL
state before removing its install manifest.

**It never deletes models or data.** Not the model store, not any model —
including ones it built — and not your sandbox, which holds your work. Those
are listed at the end with the exact command to remove them yourself if you
want to. Reinstalling later reuses the models rather than re-downloading them.

Ollama itself is left installed; uninstall it from Windows Settings → Apps.
