The \--model flag in Claude Code accepts short model aliases, 1M context variants, execution modes, and full versioned Anthropic API model identifiers.

| Category | Alias / Value | Target Version / Behavioral Role |
| :---- | :---- | :---- |
| **Sonnet Choices** | sonnet | Default alias for standard daily coding tasks; resolves to the latest Sonnet model. |
|  | sonnet\[1m\] | Sonnet configured with an extended 1-million-token context window. |
|  | Full Model IDs | claude-3-7-sonnet-20250219 (Claude 3.7 Sonnet) claude-3-5-sonnet-20241022 (Claude 3.5 Sonnet) |
| **Fable Choices** | fable | Alias for deep reasoning and long autonomous sessions; resolves to Fable 5.1. |
|  | fable\[1m\] | Fable configured with an extended 1-million-token context window. |
|  | Full Model IDs | claude-fable-5-1 (Claude Fable 5.1) claude-fable-5 (Claude Fable 5.0) |
| **Opus Choices** | opus | Alias for high-reasoning complex architectural tasks. |
|  | opus\[1m\] | Opus configured with an extended 1-million-token context window. |
|  | opusplan | Dual-mode: uses Opus during plan mode, then automatically switches to Sonnet for execution. |
|  | Full Model IDs | claude-3-opus-20240229 (Claude 3 Opus) |
| **Haiku Choices** | haiku | Alias for fast, low-cost execution on lightweight tasks. |
|  | Full Model IDs | claude-3-5-haiku-20241022 (Claude 3.5 Haiku) |
| **Special Modes** | best | Automatically routes to the latest Fable model if available on your plan, otherwise defaults to Opus. |
|  | default | Clears local model overrides and reverts to your account's runtime default. |

**CLI Syntax Examples**

* **Using Short Aliases:**  
  Bash  
  claude \--model sonnet  
  claude \--model fable  
  claude \--model sonnet\[1m\]

* **Using Full Versioned IDs:**  
  Bash  
  claude \--model claude-3-7-sonnet-20250219  
  claude \--model claude-fable-5-1

* **Inline Session Switching:**  
  Inside an active Claude Code session, run /model fable or /model sonnet to switch models dynamically without restarting the CLI.