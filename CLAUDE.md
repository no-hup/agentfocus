# AgentFocus — rules for agents working here

- The core loop (hook/emit.js → registry JSON → helper app → bin/agentfocus → adapters/) is empirically tested on real macOS. Treat it as frozen: extend by ADDING new files (per-agent shims, new adapters, new subcommands), never by editing tested paths unless the task is specifically a fix to them.
- Simplest thing that works: no new dependencies, no abstractions with one caller, shortest diff. A change's blast radius must stay inside its own new file wherever possible.
- Hard product constraints: never require Accessibility/Screen Recording/Input Monitoring; local-only (no network/telemetry); `brew install` + one command must be the whole setup.
- Verify empirically on this machine before claiming done — this repo's history is built on machine-tested claims, not plausible ones.
