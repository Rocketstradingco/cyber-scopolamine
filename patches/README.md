# Aider cyberpunk waiting-spinner + local model-picker patch

Two independent fixes bundled together since both edit installed
`aider-chat` internals:

1. **Waiting spinner:** replaces "Waiting for `<model>`" with the loading
   bar animation unchanged, but the label cycling through ~75
   unhinged/R-rated neon-hacker one-liners (`CYBERPUNK_PHRASES` in
   `aider/waiting.py`), each in a random bright color, with heavy glitch
   corruption (multi-character noise most frames, occasional full-line
   scramble) and per-frame color flicker. No model name is shown.
2. **`/model` picker:** on this offline, no-API-key box, `/model`'s
   built-in Tab-completion was pulling from litellm's ~3000-entry cloud
   model catalog (`completions_model` returning `litellm.model_cost.keys()`)
   instead of the configured Ollama alias — so pressing Tab
   either showed nothing (a separate bug: aider's completer refuses to
   complete right after a bare trailing space) or, once you typed a
   character, buried the real options among thousands of irrelevant
   cloud names. Typing a stray cloud model name and submitting it then
   fails with litellm's "LLM Provider NOT provided" error. Now `/model `
   + Tab (even with nothing typed yet) completes from the configured local
   Ollama-backed aliases, and `/model` with no argument prints
   the same local-only table with a `*` on the active one.

These patches edit the **installed** `aider-chat` package directly, not
aider's own upstream source, so they're lost on `uv tool upgrade
aider-chat` / reinstall. Reapply with:

```powershell
cyber-scopolamine-patch
```

## Files

- `0001-waiting-py.patch` — rewrites `aider/waiting.py`: the phrase
  list, color palette, glitch/scramble effects, and cycling logic in
  `Spinner`. `Spinner(text=None)` / `WaitingSpinner()` means "cyberpunk
  mode"; passing explicit text keeps the old static-label behavior
  (used elsewhere by aider's git-commit spinner, left untouched).
- `0002-base-coder-py.patch` — one-line change: `WaitingSpinner("Waiting
  for " + self.main_model.name)` → `WaitingSpinner()`, so the main LLM
  wait uses cyberpunk mode instead of showing the model name.
- `0003-commands-py.patch` — adds `Commands._local_model_aliases()`
  (aliases whose target starts with `ollama_chat/` or `ollama/`), used
  by both `cmd_model` (the no-argument printed table) and
  `completions_model` (Tab-completion candidates) so only configured local
  options are offered — the cloud catalog is still reachable via
  the separate `/models <search>` command.
- `0004-io-py.patch` — `AutoCompleter.get_completions` /
  `get_command_completions` in `aider/io.py`: previously *any* slash
  command's argument completion was blocked outright the instant a
  trailing space was typed, before candidate lookup even ran. Now a bare
  trailing space is treated as an empty partial and returns every
  candidate (sorted, arrow/Tab-navigable via prompt_toolkit's existing
  multi-column completion menu — no key-binding changes needed). This is
  a general fix, so it also applies to other commands' argument
  completion, not just `/model`.
- `apply.ps1` — locates Cyber-Scopolamine's dedicated aider environment and
  applies all four patches with Git for Windows' `patch.exe`.

## Verifying it applied

```
aider --version   # confirm which install you're patching
```

Then start a chat and trigger a model response — the label should be a
glitchy, changing colored phrase, never the model name, bar animation
intact. Type `/model` with no argument to confirm only the configured `local`
alias shows (not sonnet/opus/haiku/etc.), then type `/model ` and press Tab to
confirm it appears in the completion dropdown with nothing typed yet.
