import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { kgSend, kgResult, kgError } from "../kg/socket.js";
import { kgToolsEnabled, logKgModeOnce } from "../kg/mode.js";

/** Room access graph (connects). Forwards to `kg_compute_connects`. */
export function registerKgComputeConnectsTool(server: McpServer) {
  logKgModeOnce();
  if (!kgToolsEnabled()) return;
  server.tool(
    "kg_compute_connects",
    "Compute the room access graph: Derived connects edges (Room <-> Room) between rooms that move between via a DOOR in a shared wall OR a shared ROOM-SEPARATION LINE (open passage). Pure graph, idempotent full-replace; each edge carries via + boundary_type (door|separation|mixed). Also recomputed automatically at kg_export. Returns { pairs, computed_at_turn, connections }.",
    {},
    async () => {
      try {
        return kgResult(await kgSend("kg_compute_connects", {}));
      } catch (error) {
        return kgError(error);
      }
    }
  );
}
