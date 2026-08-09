# Contributing to Cyber-Scopolamine

Thanks for helping improve the project. Bug reports, documentation corrections,
hardware compatibility results, tests, and focused pull requests are welcome.

## Before opening an issue

Search existing issues first. For bugs, collect the smallest reproducible case
and include:

- Windows and PowerShell versions;
- GPU model and VRAM;
- Ollama and Cyber-Scopolamine versions;
- the selected model and model-store location;
- the command that failed and the exact error; and
- whether this was a clean install, upgrade, or reinstall.

Remove credentials, personal data, and unrelated source code from logs. Report
security problems using [SECURITY.md](SECURITY.md), not a public issue.

## Making a change

1. Create a branch from `main`.
2. Keep the change focused and avoid committing machine-specific paths, model
   files, generated environments, or sandbox contents.
3. Preserve compatibility with both Windows PowerShell 5.1 and PowerShell 7
   unless the change explicitly documents a compatibility break.
4. Add or update Pester tests when behavior changes.
5. Update `CHANGELOG.md` under **Unreleased** for user-visible changes.
6. Run the checks below before opening a pull request.

## Local checks

Parse every PowerShell script with both available engines:

```powershell
Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName, [ref]$tokens, [ref]$errors
    ) | Out-Null
    $errors
}
```

Run static analysis and tests when the modules are installed:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error
Invoke-Pester
```

Exercise installer or uninstaller changes with their preview/dry-run paths
first. Confirm that uninstalling preserves the model store and the user's
workspace.

## Pull requests

Explain the user-visible result, list the environments tested, and note any
known limitations. Keep refactors separate from behavior changes when practical
so the review can verify both safely.
