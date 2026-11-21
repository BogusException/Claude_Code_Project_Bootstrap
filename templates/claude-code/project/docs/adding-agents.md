# Adding Agents

## 1. Agent inventory

*List every Claude subagent or tool this project uses. Add a row each time you introduce a new one.*

| Name | Purpose | When to use |
|------|---------|-------------|
| (example) summarizer | Condenses long documents | When input exceeds context window |

## 2. Adding a new agent

*Follow these steps each time you wire in a new subagent.*

1. Define the agent's role and scope in a one-paragraph prompt.
2. Add it to the table in section 1 above.
3. Reference it in `CLAUDE.md` or call it from code -- not both.
4. Test with a representative input before relying on it in production.

## 3. Agent communication patterns

*Describe how agents hand off context to each other in this project. What data does one agent produce that the next one consumes?*

- Input format:
- Output format:
- Error handling between agents:
