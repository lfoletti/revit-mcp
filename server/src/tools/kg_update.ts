import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { kgSend, kgResult, kgError } from "../kg/socket.js";
import { kgToolsEnabled, logKgModeOnce } from "../kg/mode.js";

/** Reconcile the KG with the live model. Forwards to `kg_update`. */
export function registerKgUpdateTool(server: McpServer) {
  logKgModeOnce();
  if (!kgToolsEnabled()) return;
  server.tool(
    "kg_update",
    "Reconcile the KG projection with the live Revit document (drift detect + resolve + advance turn + flush). On a cold (cset-only) KG this triggers the first full scan via self-host. Returns { total_detected, total_resolved, turn, node_count, edge_count }.",
    {},
    async () => {
      try {
        return kgResult(await kgSend("kg_update", {}));
      } catch (error) {
        return kgError(error);
      }
    }
  );
}
