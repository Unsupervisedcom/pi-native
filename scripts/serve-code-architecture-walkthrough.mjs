#!/usr/bin/env node

import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const projectPath = resolve(repoRoot, "PiNative.xcodeproj");
const reportPath = resolve(repoRoot, "docs/code-architecture-walkthrough.html");
const host = "127.0.0.1";
const port = Number(process.env.PINATIVE_ARCHITECTURE_PORT ?? "43117");
const shouldOpen = !process.argv.includes("--no-open");

function send(response, status, body, contentType = "text/plain; charset=utf-8") {
  response.writeHead(status, {
    "Content-Type": contentType,
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  response.end(body);
}

function pathInsideRepo(relativePath) {
  if (!relativePath || isAbsolute(relativePath)) return undefined;
  const candidate = resolve(repoRoot, relativePath);
  const relation = relative(repoRoot, candidate);
  if (relation === "" || relation === ".." || relation.startsWith(`..${sep}`) || isAbsolute(relation)) return undefined;
  return candidate;
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url ?? "/", `http://${host}:${port}`);

  if (request.method !== "GET") {
    send(response, 405, "Method not allowed");
    return;
  }

  if (url.pathname === "/" || url.pathname === "/code-architecture-walkthrough.html") {
    try {
      send(response, 200, await readFile(reportPath), "text/html; charset=utf-8");
    } catch (error) {
      send(response, 500, `Could not read report: ${error.message}`);
    }
    return;
  }

  if (url.pathname === "/open") {
    const relativePath = url.searchParams.get("path") ?? "";
    const sourcePath = pathInsideRepo(relativePath);
    const requestedLine = Number.parseInt(url.searchParams.get("line") ?? "1", 10);
    const line = Number.isSafeInteger(requestedLine) && requestedLine > 0 ? requestedLine : 1;

    if (!sourcePath) {
      send(response, 400, "Invalid source path");
      return;
    }

    try {
      const sourceStat = await stat(sourcePath);
      if (!sourceStat.isFile()) throw new Error("Path is not a file");
    } catch (error) {
      send(response, 404, `Source file not found: ${relativePath}\n${error.message}`);
      return;
    }

    const child = spawn("/usr/bin/xed", ["-p", projectPath, "-l", String(line), sourcePath], {
      detached: true,
      stdio: "ignore",
    });
    child.unref();

    send(
      response,
      200,
      `<!doctype html><meta charset="utf-8"><title>Opening ${relativePath}</title><style>body{font:15px -apple-system;margin:40px;color:#333}</style><p>Opening <strong>${relativePath}</strong> in Xcode…</p><script>setTimeout(() => window.close(), 250)</script>`,
      "text/html; charset=utf-8",
    );
    return;
  }

  send(response, 404, "Not found");
});

server.on("error", (error) => {
  if (error.code === "EADDRINUSE") {
    const reportURL = `http://${host}:${port}/`;
    console.log(`Architecture walkthrough server already available at ${reportURL}`);
    if (shouldOpen) spawn("/usr/bin/open", [reportURL], { detached: true, stdio: "ignore" }).unref();
    process.exit(0);
  }
  throw error;
});

server.listen(port, host, () => {
  const reportURL = `http://${host}:${port}/`;
  console.log(`Serving PiNative architecture walkthrough at ${reportURL}`);
  console.log("Press Ctrl+C to stop.");
  if (shouldOpen) spawn("/usr/bin/open", [reportURL], { detached: true, stdio: "ignore" }).unref();
});
