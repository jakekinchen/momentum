(function () {
  const data = window.FITGRAPH_DEMO;
  let receiptFilter = "all";
  let activeReceiptId = data.generation.receipts[0].id;
  let activePrompt = data.copilot.prompts[0];

  const $ = (selector) => document.querySelector(selector);

  function create(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function clear(node) {
    node.replaceChildren();
  }

  function chip(text, className = "chip") {
    return create("span", className, text);
  }

  function sourceLabel(sourceId) {
    const source = data.sources[sourceId];
    return source ? source.title : sourceId;
  }

  function receiptById(receiptId) {
    return data.generation.receipts.find((receipt) => receipt.id === receiptId);
  }

  function renderTopbar() {
    $("#run-id").textContent = data.meta.runId;
    $("#graph-version").textContent = data.meta.graphVersion;
    $("#ontology-lock").textContent = data.meta.ontologyLockVersion;
  }

  function renderMemberContext() {
    $("#member-title").textContent = `${data.member.name} | ${data.member.tier}`;

    const queue = $("#coach-queue");
    clear(queue);
    data.coach.queue.forEach((item) => {
      const metric = create("div", "metric");
      metric.append(create("span", "value", item.value));
      metric.append(create("span", "label", item.label));
      queue.append(metric);
    });

    const goals = $("#member-goals");
    clear(goals);
    data.member.goals.forEach((goal) => goals.append(create("li", "", goal)));

    const equipment = $("#equipment-list");
    clear(equipment);
    data.member.equipment.forEach((item) => equipment.append(chip(item)));

    const restrictions = $("#restriction-list");
    clear(restrictions);
    data.member.restrictions.forEach((restriction) => {
      const card = create("div", "restriction-card");
      card.append(create("strong", "", `${restriction.label} | ${restriction.severity}`));
      card.append(create("p", "", `${restriction.since}: ${restriction.detail}`));
      restrictions.append(card);
    });

    const preferences = $("#preference-list");
    clear(preferences);
    data.member.preferences.forEach((preference) => preferences.append(create("li", "", preference)));
  }

  function renderGenerator() {
    $("#coach-prompt").value = data.workoutRequest.prompt;
    $("#minutes-input").value = data.workoutRequest.minutes;
    $("#member-input").value = `${data.member.name} (${data.member.id})`;

    const constraints = $("#constraint-list");
    clear(constraints);
    data.workoutRequest.constraints.forEach((constraint) => {
      const card = create("div", "constraint-card");
      const polarity = constraint.negated ? "negated" : "positive";
      const mode = constraint.hard ? "hard" : "soft";
      card.append(create("strong", "", `${constraint.type}: ${constraint.value}`));
      card.append(create("span", "", `${mode}, ${polarity} | ${constraint.source}`));
      constraints.append(card);
    });

    $("#generate-button").addEventListener("click", () => {
      data.workoutRequest.prompt = $("#coach-prompt").value.trim() || data.workoutRequest.prompt;
      data.workoutRequest.minutes = Number($("#minutes-input").value || data.workoutRequest.minutes);
      renderRunSummary(true);
      renderEvidence();
    });
  }

  function renderRunSummary(justRan = false) {
    const summary = data.generation.summary;
    const metrics = [
      ["Selected", summary.selectedCount],
      ["Filtered", summary.filteredCount],
      ["Alternatives", summary.alternativesCount],
      ["Safe pool", summary.safePoolCount]
    ];
    const container = $("#summary-metrics");
    clear(container);
    metrics.forEach(([label, value]) => {
      const metric = create("div", "metric");
      metric.append(create("span", "value", String(value)));
      metric.append(create("span", "label", label));
      container.append(metric);
    });
    $("#last-run").textContent = justRan ? "Generated now" : "Static demo run";
  }

  function renderPlan() {
    const list = $("#plan-list");
    clear(list);
    data.generation.selected.forEach((exercise) => {
      const card = create("article", "plan-card");
      const title = create("div");
      title.append(create("h3", "", exercise.label));
      title.append(create("p", "", exercise.reason));

      const meta = create("div", "plan-meta");
      meta.append(create("span", "", exercise.block));
      meta.append(create("span", "", exercise.prescription));
      meta.append(create("span", "", exercise.focus));
      meta.append(create("span", "", exercise.equipment.join(", ")));

      card.append(title, meta);
      list.append(card);
    });
  }

  function decisionClass(decision) {
    if (decision === "selected") return "receipt-status selected";
    if (decision === "downranked") return "receipt-status downranked";
    return "receipt-status filtered";
  }

  function filteredReceipts() {
    if (receiptFilter === "all") return data.generation.receipts;
    return data.generation.receipts.filter((receipt) => receipt.decision === receiptFilter);
  }

  function renderReceiptTable() {
    const body = $("#receipt-table");
    clear(body);

    filteredReceipts().forEach((receipt) => {
      const row = document.createElement("tr");

      const exercise = document.createElement("td");
      exercise.append(create("strong", "", receipt.label));
      exercise.append(create("div", "query", receipt.exerciseId));

      const decision = document.createElement("td");
      decision.append(create("span", decisionClass(receipt.decision), receipt.decision));

      const reason = document.createElement("td");
      reason.append(create("strong", "", receipt.primaryReasonCode));
      const reasonList = create("div", "reason-list");
      receipt.reasonCodes.forEach((reasonCode) => reasonList.append(chip(reasonCode, "reason-chip")));
      reason.append(reasonList);

      const source = document.createElement("td");
      const sourceList = create("div", "source-list");
      receipt.sourceIds.forEach((sourceId) => sourceList.append(chip(sourceLabel(sourceId), "source-chip")));
      const inspect = create("button", "receipt-action", "Inspect");
      inspect.type = "button";
      inspect.addEventListener("click", () => {
        activeReceiptId = receipt.id;
        renderEvidence();
      });
      source.append(sourceList, inspect);

      row.append(exercise, decision, reason, source);
      body.append(row);
    });
  }

  function renderReceiptFilters() {
    document.querySelectorAll("[data-filter]").forEach((button) => {
      button.addEventListener("click", () => {
        receiptFilter = button.dataset.filter;
        document.querySelectorAll("[data-filter]").forEach((item) => {
          item.classList.toggle("active", item === button);
        });
        renderReceiptTable();
      });
    });
  }

  function renderAlternatives() {
    const list = $("#alternatives-list");
    clear(list);
    data.generation.alternatives.forEach((alternative) => {
      const card = create("article", "alternative-card");
      const header = document.createElement("header");
      const title = create("div");
      title.append(create("h3", "", `${alternative.filtered} -> ${alternative.alternative}`));
      title.append(create("p", "", alternative.reason));
      header.append(title, create("span", "score", `score ${alternative.score}`));

      const paths = create("ul", "path-list");
      alternative.graphPaths.forEach((path) => paths.append(create("li", "", path)));
      card.append(header, paths);
      list.append(card);
    });
  }

  function renderCopilotPrompts() {
    const prompts = $("#copilot-prompts");
    clear(prompts);
    data.copilot.prompts.forEach((prompt) => {
      const button = create("button", "prompt-button", prompt);
      button.type = "button";
      button.classList.toggle("active", prompt === activePrompt);
      button.addEventListener("click", () => {
        activePrompt = prompt;
        renderCopilot();
      });
      prompts.append(button);
    });
  }

  function renderCopilot() {
    renderCopilotPrompts();
    const response = data.copilot.responses[activePrompt];

    const answer = $("#copilot-answer");
    clear(answer);
    answer.append(create("p", "", response.answer));

    const cards = $("#fact-cards");
    clear(cards);
    response.cards.forEach((card) => {
      const node = create("article", "fact-card");
      const header = document.createElement("header");
      header.append(create("strong", "", card.confidence));
      header.append(create("span", "query", card.query));
      node.append(header, create("p", "", card.claim));

      const sources = create("div", "source-list");
      if (card.sourceIds.length === 0) {
        sources.append(chip("no source nodes", "source-chip"));
      } else {
        card.sourceIds.forEach((sourceId) => sources.append(chip(sourceLabel(sourceId), "source-chip")));
      }
      node.append(sources);
      cards.append(node);
    });
  }

  function lineChart(container, points, options) {
    const width = 360;
    const height = 126;
    const pad = 18;
    const max = options.max;
    const min = options.min ?? 0;
    const spread = max - min || 1;
    const step = (width - pad * 2) / Math.max(points.length - 1, 1);
    const coords = points.map((point, index) => {
      const x = pad + index * step;
      const y = height - pad - ((point.value - min) / spread) * (height - pad * 2);
      return { x, y, point };
    });

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", "sparkline");
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", options.label);

    [25, 50, 75, 100].forEach((tick) => {
      const y = height - pad - ((tick - min) / spread) * (height - pad * 2);
      const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
      line.setAttribute("class", "grid");
      line.setAttribute("x1", String(pad));
      line.setAttribute("x2", String(width - pad));
      line.setAttribute("y1", String(y));
      line.setAttribute("y2", String(y));
      svg.append(line);
    });

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("class", "line");
    path.setAttribute(
      "d",
      coords.map((coord, index) => `${index === 0 ? "M" : "L"} ${coord.x} ${coord.y}`).join(" ")
    );
    svg.append(path);

    coords.forEach((coord) => {
      const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      circle.setAttribute("class", "point");
      circle.setAttribute("cx", String(coord.x));
      circle.setAttribute("cy", String(coord.y));
      circle.setAttribute("r", "4");
      svg.append(circle);

      const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
      label.setAttribute("x", String(coord.x));
      label.setAttribute("y", String(height - 2));
      label.setAttribute("text-anchor", "middle");
      label.textContent = coord.point.label.replace(" ", "\n");
      svg.append(label);
    });

    clear(container);
    container.append(svg);
  }

  function barChart(container, points, options) {
    const chart = create("div", "bar-chart");
    points.forEach((point) => {
      const item = create("div", "bar-item");
      const stack = create("div", "bar-stack");
      const bar = create("div", `bar ${options.className || ""}`);
      bar.style.height = `${Math.max(5, (point.value / options.max) * 92)}px`;
      bar.title = `${point.label}: ${point.value}`;
      stack.append(bar);
      item.append(stack, create("span", "bar-label", point.label));
      chart.append(item);
    });
    clear(container);
    container.append(chart);
  }

  function messageChart(container, points) {
    const max = Math.max(...points.flatMap((point) => [point.member, point.coach]));
    const chart = create("div", "bar-chart");
    points.forEach((point) => {
      const item = create("div", "bar-item");
      const stack = create("div", "bar-stack");
      ["member", "coach"].forEach((key) => {
        const bar = create("div", `bar ${key}`);
        bar.style.height = `${Math.max(5, (point[key] / max) * 92)}px`;
        bar.title = `${point.label} ${key}: ${point[key]}`;
        stack.append(bar);
      });
      item.append(stack, create("span", "bar-label", point.label));
      chart.append(item);
    });
    clear(container);
    container.append(chart);
  }

  function renderCharts() {
    lineChart($("#adherence-chart"), data.charts.adherence, {
      label: "Weekly adherence percentage",
      min: 0,
      max: 100
    });
    barChart($("#sleep-chart"), data.charts.sleep, { max: 8, className: "sleep" });
    messageChart($("#message-chart"), data.charts.messages);
  }

  function renderEvidence() {
    const receipt = receiptById(activeReceiptId) || data.generation.receipts[0];
    const detail = $("#evidence-detail");
    clear(detail);

    const summary = create("div", "evidence-block");
    summary.append(create("h3", "", receipt.label));
    summary.append(create("p", "", `${receipt.decision} | ${receipt.primarySeverity} | ${receipt.primaryReasonCode}`));
    const reasons = create("div", "reason-list");
    receipt.reasonCodes.forEach((reasonCode) => reasons.append(chip(reasonCode, "reason-chip")));
    summary.append(reasons);
    detail.append(summary);

    const paths = create("div", "evidence-block");
    paths.append(create("h3", "", "Graph paths"));
    const pathList = create("ul", "path-list");
    if (receipt.graphPaths.length === 0) {
      pathList.append(create("li", "", "No blocking path; selected receipt passed deterministic safety checks."));
    } else {
      receipt.graphPaths.forEach((path) => pathList.append(create("li", "", path)));
    }
    paths.append(pathList);
    detail.append(paths);

    const sourceBlock = create("div", "evidence-block");
    sourceBlock.append(create("h3", "", "Source spans"));
    const sourceList = create("div", "source-list");
    receipt.sourceIds.forEach((sourceId) => sourceList.append(chip(sourceLabel(sourceId), "source-chip")));
    sourceBlock.append(sourceList);

    receipt.sourceIds.forEach((sourceId) => {
      const source = data.sources[sourceId];
      if (!source) return;
      const sourceNode = create("div", "source-detail");
      sourceNode.append(create("p", "", `${source.path} ${source.jsonPath}`));
      sourceNode.append(create("p", "", source.excerpt));
      sourceBlock.append(sourceNode);
    });
    detail.append(sourceBlock);
  }

  function init() {
    renderTopbar();
    renderMemberContext();
    renderGenerator();
    renderRunSummary();
    renderPlan();
    renderReceiptFilters();
    renderReceiptTable();
    renderAlternatives();
    renderCopilot();
    renderCharts();
    renderEvidence();
  }

  init();
})();
