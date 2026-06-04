#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

const root = process.cwd();

function run(command, args = []) {
  try {
    return execFileSync(command, args, { cwd: root, encoding: "utf8" }).trim();
  } catch (error) {
    return (error.stdout || error.stderr || error.message || "").toString().trim();
  }
}

function section(name) {
  console.log(`\n== ${name} ==`);
}

function latestFile(dir) {
  if (!existsSync(dir)) return "";
  const files = readdirSync(dir)
    .filter((name) => name !== ".gitkeep" && name.endsWith(".md"))
    .sort();
  if (files.length === 0) return "";
  return join(dir, files[files.length - 1]);
}

function goalValue(label) {
  if (!existsSync("GOAL.md")) return "";
  const lines = readFileSync("GOAL.md", "utf8").split(/\r?\n/);
  const index = lines.findIndex((line) => line.trim() === `## ${label}`);
  if (index === -1) return "";
  for (let i = index + 1; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (line.startsWith("## ")) return "";
    if (line) return line;
  }
  return "";
}

function pidStatus(path) {
  if (!existsSync(path)) return "none";
  const pid = readFileSync(path, "utf8").trim();
  if (!pid) return "empty";
  const ps = spawnSync("ps", ["-p", pid, "-o", "pid=,etime=,command="], {
    encoding: "utf8",
  });
  if (ps.status === 0 && ps.stdout.trim()) return ps.stdout.trim();
  return `${pid} (not running)`;
}

section("Repo");
console.log(`root: ${root}`);
console.log(run("git", ["status", "--short", "--branch"]));
console.log(`head: ${run("git", ["log", "--oneline", "-1"])}`);

section("Goal");
if (existsSync("GOAL.md")) {
  const goal = readFileSync("GOAL.md", "utf8");
  console.log(`current milestone: ${goalValue("Current Milestone") || "unknown"}`);
  console.log(`current slice: ${goalValue("Current Slice") || "unknown"}`);
  console.log(`stop sentinel: ${/^<stop-orchestrator\/>$/m.test(goal) ? "present" : "absent"}`);
} else {
  console.log("GOAL.md missing");
}

section("Latest Artifacts");
for (const dir of ["docs/briefs", "docs/session-logs", "docs/reviewer-messages", "docs/manager-log"]) {
  console.log(`${dir}: ${latestFile(dir) || "none"}`);
}

section("Loop Process");
console.log(`pid: ${pidStatus(".codex-goal-loop.pid")}`);

section("Codex Logs");
for (const role of ["executor", "reviewer", "manager"]) {
  const marker = `.codex-${role}-latest-log`;
  const log = existsSync(marker) ? readFileSync(marker, "utf8").trim() : "";
  console.log(`${role}: ${log || "none"}`);
}

section("Recent Commits");
console.log(run("git", ["log", "--oneline", "-5"]));
