# GitLab Duo Setup for VS Code

GitLab Duo provides AI-powered features in your IDE, including code suggestions, code explanation, and test generation.

## Prerequisites

- VS Code installed
- GitLab account with access to vauchi group
- GitLab Ultimate (we have this via Open Source Program)

## Installation

### 1. Install GitLab Workflow Extension

```bash
code --install-extension GitLab.gitlab-workflow
```

Or search "GitLab Workflow" in VS Code Extensions.

### 2. Authenticate with GitLab

1. Open VS Code
2. Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Linux/Windows)
3. Type "GitLab: Add Account"
4. Choose "GitLab.com"
5. Follow OAuth flow to authenticate

### 3. Enable GitLab Duo Features

1. Open VS Code Settings (`Cmd+,` or `Ctrl+,`)
2. Search for "GitLab Duo"
3. Enable:
   - **GitLab Duo Code Suggestions**: AI code completion
   - **GitLab Duo Chat**: AI chat in sidebar

## Features

### Code Suggestions

As you type, GitLab Duo suggests code completions:
- Tab to accept suggestion
- Esc to dismiss
- Works with Rust, TypeScript, Kotlin, Swift

### Code Explanation

1. Select code
2. Right-click → "GitLab Duo: Explain Code"
3. AI explains what the code does

### Test Generation

1. Select a function
2. Right-click → "GitLab Duo: Generate Tests"
3. AI generates test cases

### Chat

1. Open GitLab Duo Chat from sidebar (robot icon)
2. Ask questions about code:
   - "How does this function work?"
   - "What's wrong with this code?"
   - "Refactor this to be more efficient"

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Accept suggestion | `Tab` |
| Dismiss suggestion | `Esc` |
| Trigger suggestions | `Ctrl+Space` |
| Open chat | `Cmd+Shift+G` (configurable) |

## Troubleshooting

### Suggestions not appearing

1. Check you're authenticated: `GitLab: Show Account Info`
2. Verify Duo is enabled in settings
3. Check GitLab status: https://status.gitlab.com

### "Feature not available"

- Ensure vauchi group has Ultimate tier active
- Check Open Source Program membership is active

## Resources

- [GitLab Duo Documentation](https://docs.gitlab.com/ee/user/gitlab_duo/)
- [VS Code Extension](https://marketplace.visualstudio.com/items?itemName=GitLab.gitlab-workflow)
