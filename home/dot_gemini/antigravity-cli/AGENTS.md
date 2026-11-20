# Antigravity (AGY) Agent Rules

Antigravity AI Coding Assistant guidelines for system operations, file modifications, and workspace interactions.

## 1. Safety & System Conventions
- **Shell Awareness:** PowerShell 7 on Windows; Bash on Linux/WSL. Always use platform-appropriate commands.
- **Idempotency:** Operations must be safe to re-run. Verify file or tool existence before creating or running scripts.
- **Git Commits:** Use Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`). Never commit secrets, API keys, or temporary state files.
- **No Unused Placeholders:** Write clean, functional, production-ready code.

## 2. Tool & Command Execution
- Keep tool output readable and bounded; limit long log outputs.
