// OpenCode plugin (ESM). OpenCode has no shell hooks — plugins are JS modules
// loaded from ~/.config/opencode/plugins/ or <project>/.opencode/plugins/.
//
// Event names verified against @opencode-ai/{plugin,sdk} 1.17.15 type defs AND
// against a live `opencode run` trace: the documented `session.idle` event does
// NOT fire in 1.17.15 — the real signal is `session.status` with
// `status.type === "idle"`. Both are handled; `session.idle` is compat only.
import { createRequire } from "node:module";

const { notify, clear } = createRequire(import.meta.url)("./_emit.js");

export const AgentFocus = async ({ directory }) => {
  // `session.status` idle also fires on a session that never did any work, so
  // only a busy -> idle transition means "your turn finished, come look".
  const busy = new Set();

  const done = (sessionID) =>
    notify({ tool: "opencode", id: sessionID, cwd: directory, message: "turn complete" });

  return {
    event: async ({ event }) => {
      const p = event.properties || {};
      if (event.type === "session.status") {
        if (p.status?.type === "busy") busy.add(p.sessionID);
        else if (p.status?.type === "idle" && busy.delete(p.sessionID)) done(p.sessionID);
      }
      if (event.type === "session.idle" && busy.delete(p.sessionID)) done(p.sessionID);
      // EventPermissionUpdated: { properties: Permission } — approval pending.
      // The `permission.ask` HOOK could alter the decision, so we stay read-only.
      if (event.type === "permission.updated") {
        notify({
          tool: "opencode",
          id: p.sessionID,
          cwd: directory,
          message: `needs approval: ${p.title || "tool"}`,
        });
      }
    },
    // Closest thing to UserPromptSubmit: "called when a new message is received".
    "chat.message": async ({ sessionID }) => {
      clear({ tool: "opencode", id: sessionID });
    },
  };
};
