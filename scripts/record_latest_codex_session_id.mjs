#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";

const [role, logPath, lastMessagePath = ""] = process.argv.slice(2);

if (!role || !logPath) {
  console.error("usage: record_latest_codex_session_id.mjs <role> <jsonl-log> [last-message-path]");
  process.exit(2);
}

function visit(value, found) {
  if (!value || typeof value !== "object") return;
  if (Array.isArray(value)) {
    for (const item of value) visit(item, found);
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    if (/^(session[_-]?id|conversation[_-]?id|thread[_-]?id)$/i.test(key) && typeof child === "string") {
      found.push(child);
    }
    visit(child, found);
  }
}

const found = [];
if (existsSync(logPath)) {
  const lines = readFileSync(logPath, "utf8").split(/\r?\n/).filter(Boolean);
  for (const line of lines) {
    try {
      visit(JSON.parse(line), found);
    } catch {
      // Ignore non-JSON fragments.
    }
  }
}

const unique = [...new Set(found)];
const value = unique.at(-1) || `unknown log=${logPath}`;

writeFileSync(`.codex-${role}-session-id`, `${value}\n`);
writeFileSync(`.codex-${role}-latest-log`, `${logPath}\n`);
if (lastMessagePath) {
  writeFileSync(`.codex-${role}-last-message-path`, `${lastMessagePath}\n`);
}

