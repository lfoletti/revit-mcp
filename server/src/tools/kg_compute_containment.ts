import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { kgSend, kgResult, kgError } from "../kg/socket.js";
import { kgToolsEnabled, logKgModeOnce } from "../kg/mode.js";

/** Room -> element spatial containment. Forwards to `kg_compute_containment`. */
export function registerKgComputeContainmentTool(server: McpServer) {
  logKgModeOnce();
  if (!kgToolsEnabled()) return;
  server.tool(
    "kg_compute_containment",
    "Compute spatial containment: Derived contains_element edges (Room -> ModelElement) telling which room geometrically contains each point-based element (furniture, casework, fixtures, generic models), via GetRoomAtPoint. Idempotent full-replace, Revit-side read-only. This is the per-room element INVENTORY to read (with families/types + adjacency + envelope) to infer a room's program. Also recomputed at kg_export. Returns { elements, contained, rooms, computed_at_turn }.",
    {},
    async () => {
      try {
        return kgResult(await kgSend("kg_compute_containment", {}));
      } catch (error) {
        return kgError(error);
      }
    }
  );
}
