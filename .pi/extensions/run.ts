import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

function findProjectRoot(start: string): string | null {
  let current = start;
  while (true) {
    if (existsSync(join(current, "scripts", "run-app.sh"))) return current;
    const parent = dirname(current);
    if (parent === current) return null;
    current = parent;
  }
}

function runScript(scriptPath: string, args: string[], cwd: string): Promise<{ code: number | null; output: string }> {
  return new Promise((resolve) => {
    const child = spawn(scriptPath, args, { cwd, shell: false });
    let output = "";

    child.stdout.on("data", (chunk) => { output += chunk.toString(); });
    child.stderr.on("data", (chunk) => { output += chunk.toString(); });
    child.on("error", (error) => resolve({ code: 1, output: error.message }));
    child.on("close", (code) => resolve({ code, output: output.trim() }));
  });
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("run", {
    description: "Build and relaunch PiNative from this project (/run [--clean] [--test] [--no-launch])",
    handler: async (args, ctx) => {
      const projectRoot = findProjectRoot(ctx.cwd);
      if (!projectRoot) {
        ctx.ui.notify("/run failed: scripts/run-app.sh was not found in this project.", "error");
        return;
      }

      const scriptPath = join(projectRoot, "scripts", "run-app.sh");
      const parsedArgs = args.trim().length > 0 ? args.trim().split(/\s+/) : [];
      ctx.ui.setStatus("pinative-run", "Building PiNative…");
      const result = await runScript(scriptPath, parsedArgs, projectRoot);
      ctx.ui.setStatus("pinative-run", "");

      if (result.code !== 0) {
        ctx.ui.notify(`/run failed:\n${result.output}`, "error");
        return;
      }

      ctx.ui.notify(result.output || "PiNative built and relaunch requested.", "info");
    },
  });
}
