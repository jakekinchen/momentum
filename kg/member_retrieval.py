"""Deterministic member-context retrieval for Coach Copilot fact cards."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from typing import Callable

from kg.graph_store import LocalGraph, load_member_graph


@dataclass(frozen=True)
class FactCard:
    """Deterministic graph-backed fact card for later Copilot prose."""

    claim: str
    confidence: str
    source_nodes: tuple[str, ...]
    query: str


@dataclass(frozen=True)
class QuickPrompt:
    """Prompt palette item backed by deterministic retrieval functions."""

    key: str
    label: str
    query: str


@dataclass(frozen=True)
class ChartPoint:
    """One source-backed point in a deterministic Copilot chart series."""

    x: str
    y: float
    label: str
    source_nodes: tuple[str, ...]


@dataclass(frozen=True)
class ChartSeries:
    """Deterministic chart series generated from member graph facts."""

    key: str
    title: str
    unit: str
    points: tuple[ChartPoint, ...]
    source_nodes: tuple[str, ...]
    query: str


COPILOT_QUICK_PROMPTS: tuple[QuickPrompt, ...] = (
    QuickPrompt("brief", "Show me the brief", "member_retrieval.coach_brief"),
    QuickPrompt("adherence_trend", "How is adherence trending?", "member_retrieval.adherence_trend"),
    QuickPrompt("sleep_this_week", "How did Jordan sleep this week?", "member_retrieval.sleep_this_week"),
    QuickPrompt("churn_risk", "What is the churn risk?", "member_retrieval.churn_risk"),
    QuickPrompt("message_pattern", "What is the message pattern?", "member_retrieval.message_pattern"),
    QuickPrompt(
        "compare_last_4_weeks",
        "Compare the last 4 weeks",
        "member_retrieval.compare_last_4_weeks",
    ),
)


def _graph(graph: LocalGraph | None) -> LocalGraph:
    return graph if graph is not None else load_member_graph()


def _member_exists(graph: LocalGraph, member_id: str) -> bool:
    try:
        graph.node(member_id)
    except KeyError:
        return False
    return True


def _missing_card(member_id: str, query: str) -> FactCard:
    return FactCard(
        claim=f"The graph has no supporting fact for {member_id}.",
        confidence="deterministic",
        source_nodes=(),
        query=query,
    )


def _member_label(graph: LocalGraph, member_id: str) -> str:
    return graph.node(member_id).label


def _unique(items: tuple[str, ...] | list[str]) -> tuple[str, ...]:
    seen: set[str] = set()
    unique: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            unique.append(item)
    return tuple(unique)


def _source_nodes(graph: LocalGraph, node_id: str) -> tuple[str, ...]:
    return tuple(edge.target for edge in graph.outgoing(node_id, "DERIVED_FROM"))


def _node_with_sources(graph: LocalGraph, node_id: str) -> tuple[str, ...]:
    return (node_id, *_source_nodes(graph, node_id))


def _collect_node_sources(graph: LocalGraph, node_ids: tuple[str, ...] | list[str]) -> tuple[str, ...]:
    nodes: list[str] = []
    for node_id in node_ids:
        nodes.extend(_node_with_sources(graph, node_id))
    return _unique(nodes)


def _numeric_values(values: object) -> list[float]:
    if not isinstance(values, list):
        return []
    numbers: list[float] = []
    for value in values:
        if isinstance(value, bool):
            continue
        if isinstance(value, (int, float)):
            numbers.append(float(value))
    return numbers


def _label_list(labels: tuple[str, ...]) -> str:
    return ", ".join(labels)


def _equipment_labels(properties: dict[str, object]) -> tuple[str, ...]:
    explicit_labels = properties.get("equipment_labels", [])
    if isinstance(explicit_labels, list) and explicit_labels:
        return tuple(str(label) for label in explicit_labels)

    equipment_ids = tuple(str(value) for value in properties.get("equipment_ids", []))
    return tuple(item.split(":", 1)[1].replace("_", " ") for item in equipment_ids)


def _adherence_observations(
    member_id: str,
    graph: LocalGraph,
) -> list[tuple[str, str, int, int, float]]:
    observations: list[tuple[str, str, int, int, float]] = []
    for edge in graph.outgoing(member_id, "HAS_ADHERENCE_OBSERVATION"):
        node = graph.node(edge.target)
        properties = node.properties or {}
        planned = int(properties.get("planned_sessions", 0))
        completed = int(properties.get("completed_sessions", 0))
        pct = properties.get("completion_pct")
        if isinstance(pct, bool):
            rate = completed / planned if planned else 0.0
        elif isinstance(pct, (int, float)):
            rate = float(pct) / 100.0
        else:
            rate = completed / planned if planned else 0.0
        observations.append((str(properties.get("week_start", "")), edge.target, completed, planned, rate))
    observations.sort(key=lambda item: item[0])
    return observations


def _sleep_observation(
    member_id: str,
    graph: LocalGraph,
) -> tuple[str, tuple[float, ...], str, str] | None:
    for edge in graph.outgoing(member_id, "HAS_BIOMARKER_OBSERVATION"):
        node = graph.node(edge.target)
        properties = node.properties or {}
        if properties.get("metric") != "sleep_hours" or properties.get("period") != "last_7_days":
            continue
        values = tuple(_numeric_values(properties.get("values", [])))
        if values:
            return edge.target, values, str(properties.get("unit", "hours")), str(
                properties.get("period_end", "unknown date")
            )
    return None


def _messages(member_id: str, graph: LocalGraph) -> list[tuple[str, str, str, str]]:
    rows: list[tuple[str, str, str, str]] = []
    for edge in graph.outgoing(member_id, "HAS_MESSAGE"):
        node = graph.node(edge.target)
        properties = node.properties or {}
        rows.append(
            (
                str(properties.get("ts", "")),
                edge.target,
                str(properties.get("from", "unknown")),
                str(properties.get("text", "")),
            )
        )
    rows.sort(key=lambda item: item[0])
    return rows


def _workouts(member_id: str, graph: LocalGraph) -> list[tuple[str, str, bool, bool, int, float | None]]:
    rows: list[tuple[str, str, bool, bool, int, float | None]] = []
    for edge in graph.outgoing(member_id, "HAS_WORKOUT_SESSION"):
        node = graph.node(edge.target)
        properties = node.properties or {}
        rpe_value = properties.get("rpe")
        rpe = None if isinstance(rpe_value, bool) or not isinstance(rpe_value, (int, float)) else float(rpe_value)
        rows.append(
            (
                str(properties.get("date", "")),
                edge.target,
                bool(properties.get("planned", False)),
                bool(properties.get("completed", False)),
                int(properties.get("duration_min", 0)),
                rpe,
            )
        )
    rows.sort(key=lambda item: item[0])
    return rows


def quick_prompts(member_id: str, graph: LocalGraph | None = None) -> tuple[QuickPrompt, ...]:
    """Return the deterministic Copilot prompt palette for a known member."""

    member_graph = _graph(graph)
    if not _member_exists(member_graph, member_id):
        return ()
    return COPILOT_QUICK_PROMPTS


def available_equipment(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for member equipment availability."""

    member_graph = _graph(graph)
    query = "member_retrieval.available_equipment"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    for edge in member_graph.outgoing(member_id, "HAS_EQUIPMENT_AVAILABILITY"):
        node = member_graph.node(edge.target)
        labels = _equipment_labels(node.properties or {})
        if not labels:
            continue
        cards.append(
            FactCard(
                claim=f"{_member_label(member_graph, member_id)} has available equipment: {_label_list(labels)}.",
                confidence="deterministic",
                source_nodes=(edge.target, *_source_nodes(member_graph, edge.target)),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def active_injuries(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for active injury episodes."""

    member_graph = _graph(graph)
    query = "member_retrieval.active_injuries"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    for edge in member_graph.outgoing(member_id, "HAS_INJURY"):
        node = member_graph.node(edge.target)
        properties = node.properties or {}
        if properties.get("status") != "active":
            continue
        region = str(properties.get("region_id", "unknown")).split(":", 1)[-1].replace("_", " ")
        started_at = str(properties.get("started_at", "unknown start date"))
        restrictions = tuple(str(item) for item in properties.get("restrictions", []))
        restriction_text = f" Restrictions: {'; '.join(restrictions)}." if restrictions else ""
        cards.append(
            FactCard(
                claim=(
                    f"{_member_label(member_graph, member_id)} has an active {region} "
                    f"injury episode since {started_at}.{restriction_text}"
                ),
                confidence="deterministic",
                source_nodes=(edge.target, *_source_nodes(member_graph, edge.target)),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def goals(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for active goals."""

    member_graph = _graph(graph)
    query = "member_retrieval.goals"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    for edge in member_graph.outgoing(member_id, "HAS_GOAL"):
        node = member_graph.node(edge.target)
        if (node.properties or {}).get("status") != "active":
            continue
        cards.append(
            FactCard(
                claim=f"{member_graph.node(member_id).label}'s active goal is: {node.label}.",
                confidence="deterministic",
                source_nodes=(edge.target, *_source_nodes(member_graph, edge.target)),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def adherence_trend(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards comparing adherence observations."""

    member_graph = _graph(graph)
    query = "member_retrieval.adherence_trend"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    observations = _adherence_observations(member_id, member_graph)
    if len(observations) < 2:
        return [_missing_card(member_id, query)]

    first = observations[0]
    latest = observations[-1]
    first_pct = round(first[4] * 100)
    latest_pct = round(latest[4] * 100)
    verb = "declined" if latest_pct < first_pct else "improved" if latest_pct > first_pct else "stayed flat"
    return [
        FactCard(
            claim=(
                f"Adherence {verb} from {first_pct}% ({first[2]}/{first[3]}) "
                f"on {first[0]} to {latest_pct}% ({latest[2]}/{latest[3]}) "
                f"on {latest[0]} across {len(observations)} weekly observations."
            ),
            confidence="deterministic",
            source_nodes=_collect_node_sources(member_graph, [item[1] for item in observations]),
            query=query,
        )
    ]


def adherence_chart_series(member_id: str, graph: LocalGraph | None = None) -> list[ChartSeries]:
    """Return a deterministic weekly adherence chart series."""

    member_graph = _graph(graph)
    query = "member_retrieval.adherence_chart_series"
    if not _member_exists(member_graph, member_id):
        return []

    observations = _adherence_observations(member_id, member_graph)
    if not observations:
        return []

    points = tuple(
        ChartPoint(
            x=week_start,
            y=round(rate * 100, 1),
            label=f"{round(rate * 100)}% ({completed}/{planned})",
            source_nodes=_node_with_sources(member_graph, node_id),
        )
        for week_start, node_id, completed, planned, rate in observations
    )
    return [
        ChartSeries(
            key="adherence_trend",
            title="Weekly adherence",
            unit="percent",
            points=points,
            source_nodes=_collect_node_sources(member_graph, [item[1] for item in observations]),
            query=query,
        )
    ]


def sleep_this_week(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for current-week sleep observations."""

    member_graph = _graph(graph)
    query = "member_retrieval.sleep_this_week"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    observation = _sleep_observation(member_id, member_graph)
    if observation is not None:
        node_id, values, unit, period_end = observation
        average = sum(values) / len(values)
        cards.append(
            FactCard(
                claim=(
                    f"{_member_label(member_graph, member_id)} averaged {average:.1f} {unit} "
                    f"of sleep over {len(values)} nights ending {period_end}."
                ),
                confidence="deterministic",
                source_nodes=_node_with_sources(member_graph, node_id),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def sleep_chart_series(member_id: str, graph: LocalGraph | None = None) -> list[ChartSeries]:
    """Return a deterministic seven-night sleep chart series."""

    member_graph = _graph(graph)
    query = "member_retrieval.sleep_chart_series"
    if not _member_exists(member_graph, member_id):
        return []

    observation = _sleep_observation(member_id, member_graph)
    if observation is None:
        return []

    node_id, values, unit, period_end = observation
    try:
        end_date = date.fromisoformat(period_end)
        start_date = end_date - timedelta(days=len(values) - 1)
        x_values = tuple((start_date + timedelta(days=index)).isoformat() for index in range(len(values)))
    except ValueError:
        x_values = tuple(f"night_{index + 1}" for index in range(len(values)))

    point_sources = _node_with_sources(member_graph, node_id)
    points = tuple(
        ChartPoint(
            x=x_value,
            y=value,
            label=f"{value:.1f} {unit}",
            source_nodes=point_sources,
        )
        for x_value, value in zip(x_values, values)
    )
    return [
        ChartSeries(
            key="sleep_this_week",
            title="Sleep this week",
            unit=unit,
            points=points,
            source_nodes=point_sources,
            query=query,
        )
    ]


def churn_risk(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for explicit graph-backed churn signals."""

    member_graph = _graph(graph)
    query = "member_retrieval.churn_risk"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    for edge in member_graph.outgoing(member_id, "HAS_CHURN_SIGNAL"):
        node = member_graph.node(edge.target)
        properties = node.properties or {}
        risk_level = str(properties.get("risk_level", "unknown"))
        reasons = tuple(str(reason) for reason in properties.get("reasons", []))
        observed_at = str(properties.get("observed_at", "unknown date"))
        reason_text = "; ".join(reasons) if reasons else "no graph reason recorded"
        cards.append(
            FactCard(
                claim=(
                    f"{_member_label(member_graph, member_id)} has {risk_level} churn risk "
                    f"on {observed_at} from {len(reasons)} deterministic graph reasons: {reason_text}."
                ),
                confidence="deterministic",
                source_nodes=(edge.target, *_source_nodes(member_graph, edge.target)),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def churn_risk_chart_series(member_id: str, graph: LocalGraph | None = None) -> list[ChartSeries]:
    """Return deterministic churn-reason indicator points without model scoring."""

    member_graph = _graph(graph)
    query = "member_retrieval.churn_risk_chart_series"
    if not _member_exists(member_graph, member_id):
        return []

    for edge in member_graph.outgoing(member_id, "HAS_CHURN_SIGNAL"):
        node = member_graph.node(edge.target)
        properties = node.properties or {}
        reasons = tuple(str(reason) for reason in properties.get("reasons", []))
        if not reasons:
            continue
        point_sources = _node_with_sources(member_graph, edge.target)
        return [
            ChartSeries(
                key="churn_risk",
                title="Churn risk factors",
                unit="present",
                points=tuple(
                    ChartPoint(
                        x=reason,
                        y=1.0,
                        label="present",
                        source_nodes=point_sources,
                    )
                    for reason in reasons
                ),
                source_nodes=point_sources,
                query=query,
            )
        ]
    return []


def coach_brief(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for source-backed coach briefs."""

    member_graph = _graph(graph)
    query = "member_retrieval.coach_brief"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    for edge in member_graph.outgoing(member_id, "HAS_COACH_BRIEF"):
        node = member_graph.node(edge.target)
        properties = node.properties or {}
        generated_for = str(properties.get("generated_for", "unknown date"))
        text = str(properties.get("text", "")).strip()
        if not text:
            continue
        cards.append(
            FactCard(
                claim=(
                    f"Coach brief for {_member_label(member_graph, member_id)} "
                    f"on {generated_for}: {text}"
                ),
                confidence="deterministic",
                source_nodes=(edge.target, *_source_nodes(member_graph, edge.target)),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def message_pattern(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards summarizing source-backed message history."""

    member_graph = _graph(graph)
    query = "member_retrieval.message_pattern"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    rows = _messages(member_id, member_graph)
    if not rows:
        return [_missing_card(member_id, query)]

    sender_counts: dict[str, int] = {}
    for _, _, sender, _ in rows:
        sender_counts[sender] = sender_counts.get(sender, 0) + 1
    first_date = rows[0][0].split("T", 1)[0]
    latest_date = rows[-1][0].split("T", 1)[0]
    latest_member = next((row for row in reversed(rows) if row[2] == "member"), rows[-1])
    sender_text = ", ".join(f"{sender} sent {count}" for sender, count in sorted(sender_counts.items()))
    return [
        FactCard(
            claim=(
                f"Message pattern for {_member_label(member_graph, member_id)}: "
                f"{len(rows)} messages from {first_date} to {latest_date}; {sender_text}. "
                f"Latest member message: {latest_member[3]}"
            ),
            confidence="deterministic",
            source_nodes=_collect_node_sources(member_graph, [row[1] for row in rows]),
            query=query,
        )
    ]


def message_pattern_chart_series(member_id: str, graph: LocalGraph | None = None) -> list[ChartSeries]:
    """Return deterministic message-count chart series by sender and date."""

    member_graph = _graph(graph)
    query = "member_retrieval.message_pattern_chart_series"
    if not _member_exists(member_graph, member_id):
        return []

    rows = _messages(member_id, member_graph)
    if not rows:
        return []

    series: list[ChartSeries] = []
    for sender in sorted({row[2] for row in rows}):
        grouped: dict[str, list[str]] = {}
        for timestamp, node_id, row_sender, _ in rows:
            if row_sender != sender:
                continue
            grouped.setdefault(timestamp.split("T", 1)[0], []).append(node_id)
        points = tuple(
            ChartPoint(
                x=message_date,
                y=float(len(node_ids)),
                label=f"{len(node_ids)} {sender} message{'s' if len(node_ids) != 1 else ''}",
                source_nodes=_collect_node_sources(member_graph, node_ids),
            )
            for message_date, node_ids in sorted(grouped.items())
        )
        series.append(
            ChartSeries(
                key=f"message_pattern_{sender}",
                title=f"{sender.title()} messages",
                unit="messages",
                points=points,
                source_nodes=_collect_node_sources(member_graph, [row[1] for row in rows if row[2] == sender]),
                query=query,
            )
        )
    return series


def compare_last_4_weeks(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic comparison facts for the last four graph-backed weeks."""

    member_graph = _graph(graph)
    query = "member_retrieval.compare_last_4_weeks"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    observations = _adherence_observations(member_id, member_graph)[-4:]
    workouts = _workouts(member_id, member_graph)[-4:]
    if len(observations) < 4 or len(workouts) < 4:
        return [_missing_card(member_id, query)]

    pct_values = tuple(round(item[4] * 100) for item in observations)
    completed_count = sum(1 for item in workouts if item[3])
    planned_count = sum(1 for item in workouts if item[2])
    rpes = [item[5] for item in workouts if item[3] and item[5] is not None]
    average_rpe = sum(rpes) / len(rpes) if rpes else 0.0
    return [
        FactCard(
            claim=(
                f"Last 4 weeks for {_member_label(member_graph, member_id)}: "
                f"weekly adherence was {pct_values[0]}%, {pct_values[1]}%, {pct_values[2]}%, "
                f"and {pct_values[3]}%; logged workouts completed {completed_count}/{planned_count} "
                f"with average completed-session RPE {average_rpe:.1f}."
            ),
            confidence="deterministic",
            source_nodes=_collect_node_sources(
                member_graph,
                [item[1] for item in observations] + [item[1] for item in workouts],
            ),
            query=query,
        )
    ]


def last_4_weeks_chart_series(member_id: str, graph: LocalGraph | None = None) -> list[ChartSeries]:
    """Return deterministic chart series for the last four weeks prompt."""

    member_graph = _graph(graph)
    query = "member_retrieval.last_4_weeks_chart_series"
    if not _member_exists(member_graph, member_id):
        return []

    observations = _adherence_observations(member_id, member_graph)[-4:]
    workouts = _workouts(member_id, member_graph)[-4:]
    if len(observations) < 4 or len(workouts) < 4:
        return []

    adherence_points = tuple(
        ChartPoint(
            x=item[0],
            y=round(item[4] * 100, 1),
            label=f"{round(item[4] * 100)}% ({item[2]}/{item[3]})",
            source_nodes=_node_with_sources(member_graph, item[1]),
        )
        for item in observations
    )
    workout_points = tuple(
        ChartPoint(
            x=item[0],
            y=1.0 if item[3] else 0.0,
            label="completed" if item[3] else "missed",
            source_nodes=_node_with_sources(member_graph, item[1]),
        )
        for item in workouts
    )
    return [
        ChartSeries(
            key="compare_last_4_weeks_adherence",
            title="Last 4 weeks adherence",
            unit="percent",
            points=adherence_points,
            source_nodes=_collect_node_sources(member_graph, [item[1] for item in observations]),
            query=query,
        ),
        ChartSeries(
            key="compare_last_4_weeks_workouts",
            title="Last 4 logged workouts",
            unit="completion",
            points=workout_points,
            source_nodes=_collect_node_sources(member_graph, [item[1] for item in workouts]),
            query=query,
        ),
    ]


def _prompt_key(prompt_key: str) -> str:
    normalized = prompt_key.strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "show_brief": "brief",
        "coach_brief": "brief",
        "morning_brief": "brief",
        "adherence": "adherence_trend",
        "sleep": "sleep_this_week",
        "churn": "churn_risk",
        "messages": "message_pattern",
        "message_patterns": "message_pattern",
        "compare": "compare_last_4_weeks",
        "last_4_weeks": "compare_last_4_weeks",
    }
    return aliases.get(normalized, normalized)


_FACT_CARD_FUNCTIONS: dict[str, Callable[[str, LocalGraph | None], list[FactCard]]] = {
    "brief": coach_brief,
    "adherence_trend": adherence_trend,
    "sleep_this_week": sleep_this_week,
    "churn_risk": churn_risk,
    "message_pattern": message_pattern,
    "compare_last_4_weeks": compare_last_4_weeks,
}


_CHART_SERIES_FUNCTIONS: dict[str, Callable[[str, LocalGraph | None], list[ChartSeries]]] = {
    "adherence_trend": adherence_chart_series,
    "sleep_this_week": sleep_chart_series,
    "churn_risk": churn_risk_chart_series,
    "message_pattern": message_pattern_chart_series,
    "compare_last_4_weeks": last_4_weeks_chart_series,
}


def copilot_fact_cards(
    member_id: str,
    prompt_key: str,
    graph: LocalGraph | None = None,
) -> list[FactCard]:
    """Resolve a quick prompt key to deterministic graph-backed fact cards."""

    key = _prompt_key(prompt_key)
    fact_function = _FACT_CARD_FUNCTIONS.get(key)
    if fact_function is None:
        return [_missing_card(member_id, f"member_retrieval.{key}")]
    return fact_function(member_id, graph)


def copilot_chart_series(
    member_id: str,
    prompt_key: str,
    graph: LocalGraph | None = None,
) -> list[ChartSeries]:
    """Resolve a quick prompt key to deterministic chart series, when chartable."""

    chart_function = _CHART_SERIES_FUNCTIONS.get(_prompt_key(prompt_key))
    if chart_function is None:
        return []
    return chart_function(member_id, graph)
