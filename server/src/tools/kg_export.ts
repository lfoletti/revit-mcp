import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { kgSend, kgResult, kgError } from "../kg/socket.js";
import { kgToolsEnabled, logKgModeOnce } from "../kg/mode.js";

/** Reconcile then write the fused sidecar JSON. Forwards to `kg_export`. */
export function registerKgExportTool(server: McpServer) {
  logKgModeOnce();
  if (!kgToolsEnabled()) return;
  server.tool(
    "kg_export",
    "Reconcile then write the fused sidecar JSON (attrs + live quantities + drift_status + ontology). Optional 'path'; otherwise <basename>_kg.json next to the .rvt (an unsaved document requires an explicit path). Returns { path, turn, node_count, edge_count }.",
    {
      path: z
        .string()
        .optional()
        .describe(
          "Optional output path for the JSON. Defaults to <basename>_kg.json next to the .rvt; required if the document is unsaved."
        ),
    },
    async (args) => {
      try {
        return kgResult(await kgSend("kg_export", args));
      } catch (error) {
        return kgError(error);
      }
    }
  );
}
