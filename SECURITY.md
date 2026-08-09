# Security policy

## Supported versions

Cyber-Scopolamine is currently maintained on the `main` branch. Security fixes
will be included in the next tagged release. Older snapshots may not receive
backports.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Email
`rocketstradingco@gmail.com` with:

- a concise description of the problem and its impact;
- the affected Cyber-Scopolamine version or commit;
- reproducible steps or a proof of concept;
- the Windows, PowerShell, Ollama, and aider versions involved; and
- any suggested mitigation, if known.

Remove API keys, credentials, personal data, and unrelated project files from
logs before sending them. A maintainer will acknowledge the report when it has
been received and coordinate disclosure after a fix is available.

## Scope notes

The project launches local tools with the permissions of the signed-in Windows
user. Its workspace is an organizational boundary, not an operating-system
security boundary. Reports demonstrating access beyond the workspace are most
useful when they identify an unexpected action by Cyber-Scopolamine itself,
rather than access the Windows user already possesses.
