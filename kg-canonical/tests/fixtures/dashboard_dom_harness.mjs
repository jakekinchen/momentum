import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

class Element {
  constructor(tagName) {
    this.tagName = tagName.toLowerCase();
    this.children = [];
    this.parentNode = null;
    this.attributes = new Map();
    this.dataset = {};
    this.eventListeners = new Map();
    this.style = {};
    this._textContent = "";
    this.className = "";
    this.id = "";
    this.value = "";
    this.type = "";
    this.title = "";
  }

  append(...nodes) {
    for (const node of nodes) {
      const child = typeof node === "string" ? new TextNode(node) : node;
      child.parentNode = this;
      this.children.push(child);
    }
  }

  replaceChildren(...nodes) {
    this.children = [];
    this._textContent = "";
    this.append(...nodes);
  }

  setAttribute(name, value) {
    const stringValue = String(value);
    this.attributes.set(name, stringValue);
    if (name === "id") {
      this.id = stringValue;
    } else if (name === "class") {
      this.className = stringValue;
    } else if (name.startsWith("data-")) {
      this.dataset[toDatasetKey(name.slice(5))] = stringValue;
    } else {
      this[name] = stringValue;
    }
  }

  getAttribute(name) {
    if (name === "id") return this.id || null;
    if (name === "class") return this.className || null;
    if (name.startsWith("data-")) return this.dataset[toDatasetKey(name.slice(5))] || null;
    return this.attributes.has(name) ? this.attributes.get(name) : null;
  }

  addEventListener(type, listener) {
    if (!this.eventListeners.has(type)) {
      this.eventListeners.set(type, []);
    }
    this.eventListeners.get(type).push(listener);
  }

  click() {
    for (const listener of this.eventListeners.get("click") || []) {
      listener({ currentTarget: this, target: this });
    }
  }

  get classList() {
    const element = this;
    return {
      add(...names) {
        const classes = new Set(element.className.split(/\s+/).filter(Boolean));
        names.forEach((name) => classes.add(name));
        element.className = Array.from(classes).join(" ");
      },
      contains(name) {
        return element.className.split(/\s+/).filter(Boolean).includes(name);
      },
      remove(...names) {
        const removeSet = new Set(names);
        element.className = element.className
          .split(/\s+/)
          .filter((name) => name && !removeSet.has(name))
          .join(" ");
      },
      toggle(name, force) {
        const hasClass = this.contains(name);
        const shouldHave = force === undefined ? !hasClass : Boolean(force);
        if (shouldHave) {
          this.add(name);
        } else {
          this.remove(name);
        }
        return shouldHave;
      }
    };
  }

  get textContent() {
    return `${this._textContent}${this.children.map((child) => child.textContent).join("")}`;
  }

  set textContent(value) {
    this._textContent = String(value);
    this.children = [];
  }

  querySelector(selector) {
    return querySelectorAll(this, selector)[0] || null;
  }

  querySelectorAll(selector) {
    return querySelectorAll(this, selector);
  }
}

class TextNode {
  constructor(text) {
    this.textContent = text;
    this.parentNode = null;
  }
}

class Document {
  constructor() {
    this.body = new Element("body");
  }

  createElement(tagName) {
    return new Element(tagName);
  }

  createElementNS(_namespace, tagName) {
    return new Element(tagName);
  }

  querySelector(selector) {
    return this.body.querySelector(selector);
  }

  querySelectorAll(selector) {
    return this.body.querySelectorAll(selector);
  }
}

function toDatasetKey(raw) {
  return raw.replace(/-([a-z])/g, (_match, char) => char.toUpperCase());
}

function descendants(root) {
  const nodes = [];
  for (const child of root.children || []) {
    if (child instanceof Element) {
      nodes.push(child);
      nodes.push(...descendants(child));
    }
  }
  return nodes;
}

function querySelectorAll(root, selector) {
  const selectors = selector.split(",").map((item) => item.trim()).filter(Boolean);
  const found = [];
  for (const singleSelector of selectors) {
    const parts = singleSelector.split(/\s+/).filter(Boolean);
    const matches = descendants(root).filter((node) => matchesSelectorChain(node, parts));
    for (const match of matches) {
      if (!found.includes(match)) found.push(match);
    }
  }
  return found;
}

function matchesSelectorChain(node, parts) {
  if (parts.length === 0 || !matchesSimpleSelector(node, parts[parts.length - 1])) {
    return false;
  }
  let current = node.parentNode;
  for (let index = parts.length - 2; index >= 0; index -= 1) {
    while (current && !matchesSimpleSelector(current, parts[index])) {
      current = current.parentNode;
    }
    if (!current) return false;
    current = current.parentNode;
  }
  return true;
}

function matchesSimpleSelector(node, selector) {
  if (!(node instanceof Element)) return false;
  const attributeMatch = selector.match(/^\[data-([a-z0-9-]+)(?:="([^"]+)")?\]$/i);
  if (attributeMatch) {
    const value = node.dataset[toDatasetKey(attributeMatch[1])];
    return attributeMatch[2] === undefined ? value !== undefined : value === attributeMatch[2];
  }

  const idMatch = selector.match(/#([a-zA-Z0-9_-]+)/);
  if (idMatch && node.id !== idMatch[1]) return false;

  const classMatches = [...selector.matchAll(/\.([a-zA-Z0-9_-]+)/g)].map((match) => match[1]);
  const classSet = new Set(node.className.split(/\s+/).filter(Boolean));
  if (classMatches.some((className) => !classSet.has(className))) return false;

  const tag = selector.replace(/[#.][a-zA-Z0-9_-]+/g, "");
  return tag === "" || node.tagName === tag.toLowerCase();
}

function element(document, tagName, options = {}) {
  const node = document.createElement(tagName);
  if (options.id) node.setAttribute("id", options.id);
  if (options.className) node.className = options.className;
  if (options.text) node.textContent = options.text;
  if (options.type) node.type = options.type;
  if (options.data) {
    for (const [key, value] of Object.entries(options.data)) {
      node.setAttribute(`data-${key}`, value);
    }
  }
  return node;
}

function buildDocument() {
  const document = new Document();
  const ids = [
    "run-id",
    "graph-version",
    "ontology-lock",
    "member-title",
    "coach-queue",
    "member-goals",
    "equipment-list",
    "restriction-list",
    "preference-list",
    "coach-prompt",
    "minutes-input",
    "member-input",
    "constraint-list",
    "generate-button",
    "last-run",
    "summary-metrics",
    "plan-list",
    "receipt-table",
    "alternatives-list",
    "copilot-prompts",
    "copilot-answer",
    "fact-cards",
    "adherence-chart",
    "sleep-chart",
    "message-chart",
    "evidence-detail"
  ];

  for (const id of ids) {
    const tag = id === "coach-prompt" ? "textarea" : id.endsWith("input") ? "input" : "div";
    const node = element(document, tag, { id });
    document.body.append(node);
  }

  document.querySelector("#generate-button").tagName = "button";
  document.querySelector("#generate-button").textContent = "Generate";
  document.querySelector("#minutes-input").type = "number";
  document.querySelector("#member-input").type = "text";

  const filterGroup = element(document, "div", { id: "receipt-filters" });
  for (const filter of ["all", "selected", "filtered"]) {
    filterGroup.append(
      element(document, "button", {
        className: filter === "all" ? "segment active" : "segment",
        text: filter === "all" ? "All" : filter === "selected" ? "Kept" : "Filtered",
        data: { filter }
      })
    );
  }
  document.body.append(filterGroup);
  return document;
}

function text(selector) {
  return document.querySelector(selector)?.textContent.trim() || "";
}

function rows() {
  return document.querySelectorAll("#receipt-table tr");
}

function clickButtonByText(selector, buttonText) {
  const button = document
    .querySelectorAll(selector)
    .find((candidate) => candidate.textContent.trim() === buttonText);
  if (!button) {
    throw new Error(`Button not found: ${buttonText}`);
  }
  button.click();
  return button;
}

function clickInspectForExercise(label) {
  const row = rows().find((candidate) => candidate.textContent.includes(label));
  if (!row) {
    throw new Error(`Receipt row not found: ${label}`);
  }
  const inspect = row.querySelector("button");
  if (!inspect) {
    throw new Error(`Inspect button missing for: ${label}`);
  }
  inspect.click();
}

const document = buildDocument();
const context = {
  console,
  document,
  window: { document },
  Math,
  Number,
  String,
  Array,
  Object,
  Set,
  Map
};
context.window.window = context.window;
vm.createContext(context);
vm.runInContext(
  fs.readFileSync(path.join(repoRoot, "dashboard/fixtures/demo.js"), "utf8"),
  context,
  { filename: "dashboard/fixtures/demo.js" }
);
vm.runInContext(
  fs.readFileSync(path.join(repoRoot, "dashboard/app.js"), "utf8"),
  context,
  { filename: "dashboard/app.js" }
);

const initial = {
  runId: text("#run-id"),
  graphVersion: text("#graph-version"),
  ontologyLock: text("#ontology-lock"),
  memberTitle: text("#member-title"),
  planCards: document.querySelectorAll(".plan-card").length,
  receiptRows: rows().length,
  alternatives: document.querySelectorAll(".alternative-card").length,
  prompts: document.querySelectorAll(".prompt-button").map((button) => button.textContent.trim()),
  factCards: document.querySelectorAll(".fact-card").length,
  evidenceTitle: text("#evidence-detail h3"),
  charts: {
    adherenceSvg: document.querySelectorAll("#adherence-chart svg").length,
    sleepBars: document.querySelectorAll("#sleep-chart .bar").length,
    messageBars: document.querySelectorAll("#message-chart .bar").length
  }
};

clickButtonByText("[data-filter]", "Filtered");
const afterFiltered = {
  activeFilter: document.querySelector(".segment.active").dataset.filter,
  receiptRows: rows().length,
  rowText: rows().map((row) => row.textContent)
};

clickButtonByText("[data-filter]", "All");
clickInspectForExercise("Kettlebell Deadlift");
const afterEvidenceInspect = {
  evidenceTitle: text("#evidence-detail h3"),
  evidenceText: text("#evidence-detail")
};

clickButtonByText(".prompt-button", "Churn risk");
const afterCopilotPrompt = {
  activePrompt: document.querySelector(".prompt-button.active").textContent.trim(),
  answer: text("#copilot-answer"),
  factCards: document.querySelectorAll(".fact-card").length,
  factText: text("#fact-cards")
};

document.querySelector("#generate-button").click();
const afterGenerate = {
  lastRun: text("#last-run")
};

process.stdout.write(
  JSON.stringify(
    {
      initial,
      afterFiltered,
      afterEvidenceInspect,
      afterCopilotPrompt,
      afterGenerate
    },
    null,
    2
  )
);
