"""Import the external candidate-assessment fixtures into typed graph snapshots."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from typing import Any

from kg.graph_store import REPO_ROOT


MONOREPO_ROOT = REPO_ROOT.parent
ASSESSMENT_SOURCE_ROOT = "data/golden/candidate-assessment"
ASSESSMENT_DATA_SOURCE_ROOT = f"{ASSESSMENT_SOURCE_ROOT}/data"
ASSESSMENT_DIR = MONOREPO_ROOT / ASSESSMENT_SOURCE_ROOT
DATA_DIR = ASSESSMENT_DIR / "data"
EXERCISES_PATH = DATA_DIR / "exercises.json"
MEMBER_CONTEXT_PATH = DATA_DIR / "member-context.json"
GENERATED_DIR = REPO_ROOT / "graph" / "generated"
SOURCE_SNAPSHOT_COMMIT = "4b8c67246a659c26bd222079c5c7829d295acad9"
EXERCISES_SOURCE_FILE = f"{ASSESSMENT_DATA_SOURCE_ROOT}/exercises.json"
MEMBER_CONTEXT_SOURCE_FILE = f"{ASSESSMENT_DATA_SOURCE_ROOT}/member-context.json"


@dataclass(frozen=True)
class AssessmentImportArtifacts:
    """Generated assessment graph payloads and conformance summary."""

    exercise_graph: dict[str, Any]
    member_graph: dict[str, Any]
    conformance_summary: dict[str, Any]


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "_", value.strip().lower())
    return normalized.strip("_") or "unknown"


def _node(
    node_id: str,
    node_type: str,
    label: str,
    *,
    aliases: list[str] | None = None,
    properties: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "id": node_id,
        "type": node_type,
        "label": label,
        "aliases": aliases or [],
        "properties": properties or {},
    }


def _edge(
    source: str,
    predicate: str,
    target: str,
    *,
    properties: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "source": source,
        "predicate": predicate,
        "target": target,
        "properties": properties or {},
    }


def _source_span(
    span_id: str,
    *,
    source_file: str,
    json_path: str,
    source_hash: str,
    text: str,
    timestamp: str | None = None,
) -> dict[str, Any]:
    properties = {
        "source_file": source_file,
        "json_path": json_path,
        "text": text,
        "source_hash": source_hash,
        "source_snapshot_commit": SOURCE_SNAPSHOT_COMMIT,
        "synthetic_data": True,
    }
    if timestamp:
        properties["timestamp"] = timestamp
    return _node(
        span_id,
        "SourceSpan",
        json_path,
        properties=properties,
    )


def _priority_score(priority_tier: Any) -> float:
    try:
        tier = int(priority_tier)
    except (TypeError, ValueError):
        return 0.5
    return max(0.1, min(1.0, 1.0 - ((tier - 1) * 0.15)))


def _exercise_family_ids(name: str, patterns: list[str]) -> list[str]:
    text = f"{name} {' '.join(patterns)}".lower()
    families = {
        "deadlift_family": ("deadlift", "rdl", "romanian deadlift"),
        "squat_family": ("squat",),
        "lunge_family": ("lunge", "split squat"),
        "jump_family": ("jump", "plyometric"),
        "burpee_family": ("burpee",),
        "press_family": ("press", "push-up"),
        "row_family": ("row",),
        "pull_family": ("pull-up", "chin-up", "pull-down", "pulldown"),
        "carry_family": ("carry",),
        "mobility_family": ("mobility", "stretch", "yoga", "regen"),
        "core_family": ("core", "plank"),
    }
    return [
        family_id
        for family_id, tokens in families.items()
        if any(token in text for token in tokens)
    ]


def _stress_properties(
    *,
    exercise: dict[str, Any],
    region: str,
) -> dict[str, Any]:
    name = str(exercise.get("name", "")).lower()
    patterns = [str(pattern).lower() for pattern in exercise.get("movement_patterns", [])]
    equipment = [str(item).lower() for item in exercise.get("equipment_required", [])]
    weighted = bool(exercise.get("supports_weight")) or bool(equipment)
    high_load_tokens = ("barbell", "plate", "rack", "machine", "sandbag")
    medium_load_tokens = ("dumbbell", "kettlebell", "medicine ball", "ez bar")
    impact_high = "jump" in name or any("plyometric" in pattern for pattern in patterns)
    knee_pattern = any(
        token in " ".join(patterns)
        for token in ("squat", "lunge", "split squat", "step-up")
    )
    lumbar_pattern = region in {"lumbar spine", "thoracic spine"} and any(
        token in " ".join(patterns) for token in ("hinge", "carry", "rotation")
    )

    if any(token in item for item in equipment for token in high_load_tokens):
        load_level = "high"
    elif any(token in item for item in equipment for token in medium_load_tokens):
        load_level = "medium"
    elif weighted:
        load_level = "medium"
    else:
        load_level = "low"

    flexion_depth = "none"
    if region == "knee" and knee_pattern:
        flexion_depth = "deep" if load_level in {"medium", "high"} else "moderate"
    elif region in {"hip", "ankle"} and knee_pattern:
        flexion_depth = "moderate"
    elif lumbar_pattern:
        flexion_depth = "moderate"

    return {
        "source_field": "joints_loaded",
        "loaded": weighted,
        "load_level": load_level,
        "impact_level": "high" if impact_high else "low",
        "flexion_depth": flexion_depth,
        "axial_load": "high"
        if any(token in item for item in equipment for token in ("barbell", "rack", "plate"))
        else "low"
        if weighted
        else "none",
        "balance_demand": "high"
        if "bosu" in " ".join(equipment) or any("balance" in pattern for pattern in patterns)
        else "medium"
        if "single" in name
        else "low",
        "laterality": str(exercise.get("side") or "neutral"),
        "curation_status": "deterministic_import_rule",
    }


def _add_unique_node(nodes: dict[str, dict[str, Any]], node: dict[str, Any]) -> None:
    nodes.setdefault(node["id"], node)


def _build_exercise_graph(exercises: list[dict[str, Any]], source_hash: str) -> dict[str, Any]:
    nodes: dict[str, dict[str, Any]] = {}
    edges: list[dict[str, Any]] = []

    source_file = EXERCISES_SOURCE_FILE
    family_labels = {
        "deadlift_family": "Deadlift Family",
        "squat_family": "Squat Family",
        "lunge_family": "Lunge Family",
        "jump_family": "Jump Family",
        "burpee_family": "Burpee Family",
        "press_family": "Press Family",
        "row_family": "Row Family",
        "pull_family": "Pull Family",
        "carry_family": "Carry Family",
        "mobility_family": "Mobility Family",
        "core_family": "Core Family",
    }
    for family_id, label in family_labels.items():
        _add_unique_node(
            nodes,
            _node(
                f"ExerciseFamily:{family_id}",
                "ExerciseFamily",
                label,
                aliases=[label.lower().replace(" family", ""), family_id.replace("_", " ")],
                properties={"curation_status": "deterministic_import_rule"},
            ),
        )

    for region in (
        "knee",
        "left knee",
        "right knee",
        "patella",
        "patellar tendon",
        "lower back",
        "lumbar spine",
    ):
        node_id = f"BodyRegion:{_slug(region)}"
        _add_unique_node(
            nodes,
            _node(
                node_id,
                "BodyRegion",
                region,
                aliases=[region],
                properties={"laterality": region.split(" ", 1)[0] if " " in region else "neutral"},
            ),
        )
    edges.extend(
        [
            _edge("BodyRegion:left_knee", "PART_OF", "BodyRegion:knee"),
            _edge("BodyRegion:right_knee", "PART_OF", "BodyRegion:knee"),
            _edge("BodyRegion:patella", "PART_OF", "BodyRegion:knee"),
            _edge("BodyRegion:patellar_tendon", "PART_OF", "BodyRegion:knee"),
            _edge("BodyRegion:lower_back", "PART_OF", "BodyRegion:lumbar_spine"),
        ]
    )

    for index, exercise in enumerate(exercises):
        exercise_id = f"Exercise:{_slug(str(exercise['name']))}"
        span_id = f"SourceSpan:assessment_exercise_{index:03d}"
        _add_unique_node(
            nodes,
            _source_span(
                span_id,
                source_file=source_file,
                json_path=f"$[{index}]",
                source_hash=source_hash,
                text=json.dumps(exercise, sort_keys=True),
            ),
        )
        _add_unique_node(
            nodes,
            _node(
                exercise_id,
                "Exercise",
                str(exercise["name"]),
                aliases=[str(exercise["name"]).lower()],
                properties={
                    "source_exercise_id": exercise["id"],
                    "source_fields": dict(exercise),
                    "priority_tier": exercise.get("priority_tier"),
                    "priority_score": _priority_score(exercise.get("priority_tier")),
                    "supports_weight": bool(exercise.get("supports_weight")),
                    "is_reps": bool(exercise.get("is_reps")),
                    "is_duration": bool(exercise.get("is_duration")),
                    "estimated_rep_duration": exercise.get("estimated_rep_duration"),
                    "source_snapshot_commit": SOURCE_SNAPSHOT_COMMIT,
                    "synthetic_data": True,
                },
            ),
        )
        edges.append(_edge(exercise_id, "DERIVED_FROM", span_id))

        for muscle in exercise.get("muscle_groups", []):
            muscle_id = f"MuscleGroup:{_slug(str(muscle))}"
            _add_unique_node(
                nodes,
                _node(muscle_id, "MuscleGroup", str(muscle), aliases=[str(muscle).lower()]),
            )
            edges.append(_edge(exercise_id, "TARGETS", muscle_id, properties={"source_field": "muscle_groups"}))

        for region in exercise.get("joints_loaded", []):
            region_id = f"BodyRegion:{_slug(str(region))}"
            _add_unique_node(
                nodes,
                _node(
                    region_id,
                    "BodyRegion",
                    str(region),
                    aliases=[str(region).lower()],
                    properties={"laterality": "neutral"},
                ),
            )
            edges.append(
                _edge(
                    exercise_id,
                    "STRESSES",
                    region_id,
                    properties=_stress_properties(exercise=exercise, region=str(region).lower()),
                )
            )

        patterns_lower = [str(pattern).lower() for pattern in exercise.get("movement_patterns", [])]
        name_lower = str(exercise.get("name", "")).lower()
        joint_slugs = {_slug(str(region)) for region in exercise.get("joints_loaded", [])}
        if ("knee" not in joint_slugs) and (
            "jump" in name_lower or any("plyometric" in pattern for pattern in patterns_lower)
        ):
            edges.append(
                _edge(
                    exercise_id,
                    "STRESSES",
                    "BodyRegion:knee",
                    properties={
                        "source_field": "curation:high_impact_jumping",
                        "loaded": False,
                        "load_level": "low",
                        "impact_level": "high",
                        "flexion_depth": "moderate",
                        "axial_load": "none",
                        "balance_demand": "medium",
                        "laterality": "neutral",
                        "curation_status": "conservative_high_impact_knee_rule",
                    },
                )
            )

        for pattern in exercise.get("movement_patterns", []):
            pattern_id = f"MovementPattern:{_slug(str(pattern))}"
            _add_unique_node(
                nodes,
                _node(
                    pattern_id,
                    "MovementPattern",
                    str(pattern),
                    aliases=[str(pattern).lower()],
                ),
            )
            edges.append(_edge(exercise_id, "HAS_PATTERN", pattern_id, properties={"source_field": "movement_patterns"}))

        for equipment in exercise.get("equipment_required", []):
            equipment_id = f"Equipment:{_slug(str(equipment))}"
            aliases = [str(equipment).lower()]
            if equipment == "Dumbbell":
                aliases.extend(["dumbbell", "dumbbells", "db"])
            if equipment == "Kettlebell":
                aliases.extend(["kettlebell", "kb"])
            _add_unique_node(
                nodes,
                _node(equipment_id, "Equipment", str(equipment), aliases=sorted(set(aliases))),
            )
            edges.append(_edge(exercise_id, "REQUIRES", equipment_id, properties={"source_field": "equipment_required"}))

        for family_id in _exercise_family_ids(
            str(exercise["name"]),
            [str(pattern) for pattern in exercise.get("movement_patterns", [])],
        ):
            edges.append(_edge(exercise_id, "VARIANT_OF", f"ExerciseFamily:{family_id}"))

    return {
        "schema_version": "0.1.0",
        "graph_version": "assessment-fixture-generated-v0",
        "status": "generated",
        "description": "Generated from the frozen candidate-assessment synthetic exercise fixture.",
        "source": {
            "path": source_file,
            "sha256": source_hash,
            "source_snapshot_commit": SOURCE_SNAPSHOT_COMMIT,
        },
        "nodes": [nodes[node_id] for node_id in sorted(nodes)],
        "edges": sorted(edges, key=lambda edge: (edge["source"], edge["predicate"], edge["target"])),
    }


def _member_source_span(
    nodes: dict[str, dict[str, Any]],
    *,
    span_id: str,
    json_path: str,
    value: Any,
    source_hash: str,
    timestamp: str | None = None,
) -> str:
    _add_unique_node(
        nodes,
        _source_span(
            span_id,
            source_file=MEMBER_CONTEXT_SOURCE_FILE,
            json_path=json_path,
            source_hash=source_hash,
            text=json.dumps(value, sort_keys=True),
            timestamp=timestamp,
        ),
    )
    return span_id


def _build_member_graph(member: dict[str, Any], source_hash: str) -> dict[str, Any]:
    nodes: dict[str, dict[str, Any]] = {}
    edges: list[dict[str, Any]] = []
    profile = member["profile"]
    member_id = "Member:jordan"

    profile_span = _member_source_span(
        nodes,
        span_id="SourceSpan:assessment_member_profile",
        json_path="$.profile",
        value=profile,
        source_hash=source_hash,
    )
    _add_unique_node(
        nodes,
        _node(
            member_id,
            "Member",
            str(profile["name"]),
            aliases=[str(profile["name"]), "Jordan"],
            properties={**profile, "source_snapshot_commit": SOURCE_SNAPSHOT_COMMIT, "synthetic_data": True},
        ),
    )
    edges.append(_edge(member_id, "DERIVED_FROM", profile_span))

    for index, goal in enumerate(member.get("goals", [])):
        node_id = f"Goal:{_slug(str(goal['id']))}"
        span_id = _member_source_span(
            nodes,
            span_id=f"SourceSpan:assessment_goal_{index:02d}",
            json_path=f"$.goals[{index}]",
            value=goal,
            source_hash=source_hash,
        )
        _add_unique_node(
            nodes,
            _node(node_id, "Goal", str(goal["text"]), properties={**goal, "status": "active"}),
        )
        edges.extend([_edge(member_id, "HAS_GOAL", node_id), _edge(node_id, "DERIVED_FROM", span_id)])

    preferences = member.get("preferences", {})
    pref_span = _member_source_span(
        nodes,
        span_id="SourceSpan:assessment_preferences",
        json_path="$.preferences",
        value=preferences,
        source_hash=source_hash,
    )
    pref_id = "Preference:jordan_training_preferences"
    _add_unique_node(nodes, _node(pref_id, "Preference", "Jordan training preferences", properties=preferences))
    edges.extend([_edge(member_id, "HAS_PREFERENCE", pref_id), _edge(pref_id, "DERIVED_FROM", pref_span)])

    equipment = member.get("equipment_available", [])
    equipment_span = _member_source_span(
        nodes,
        span_id="SourceSpan:assessment_equipment_available",
        json_path="$.equipment_available",
        value=equipment,
        source_hash=source_hash,
    )
    equipment_id = "EquipmentAvailability:jordan_home_equipment_assessment"
    _add_unique_node(
        nodes,
        _node(
            equipment_id,
            "EquipmentAvailability",
            "Jordan home equipment",
            aliases=["home equipment"],
            properties={"equipment_ids": [f"Equipment:{_slug(str(item))}" for item in equipment], "equipment_labels": equipment},
        ),
    )
    edges.extend(
        [
            _edge(member_id, "HAS_EQUIPMENT_AVAILABILITY", equipment_id),
            _edge(equipment_id, "DERIVED_FROM", equipment_span),
        ]
    )

    for index, injury in enumerate(member.get("injuries", [])):
        injury_id = f"InjuryEpisode:{_slug(str(injury['id']))}"
        span_id = _member_source_span(
            nodes,
            span_id=f"SourceSpan:assessment_injury_{index:02d}",
            json_path=f"$.injuries[{index}]",
            value=injury,
            source_hash=source_hash,
        )
        _add_unique_node(
            nodes,
            _node(
                injury_id,
                "InjuryEpisode",
                str(injury["region"]),
                aliases=[str(injury["region"])],
                properties={
                    **injury,
                    "status": "active" if injury.get("status") in {"recovering", "active"} else injury.get("status"),
                    "region_id": f"BodyRegion:{_slug(str(injury['region']))}",
                    "joint_id": f"BodyRegion:{_slug(str(injury['joint']))}",
                    "verified": False,
                },
            ),
        )
        edges.extend([_edge(member_id, "HAS_INJURY", injury_id), _edge(injury_id, "DERIVED_FROM", span_id)])
        for restriction_text in (
            "avoid deep knee flexion under load",
            "avoid plyometrics",
            "avoid high-impact jumping",
        ):
            restriction_id = f"Restriction:{_slug(str(injury['id']))}_{_slug(restriction_text)}"
            _add_unique_node(
                nodes,
                _node(
                    restriction_id,
                    "Restriction",
                    restriction_text,
                    properties={
                        "restriction_text": restriction_text,
                        "hard": True,
                        "source": "injury notes",
                    },
                ),
            )
            edges.extend(
                [
                    _edge(injury_id, "HAS_RESTRICTION", restriction_id),
                    _edge(restriction_id, "DERIVED_FROM", span_id),
                ]
            )

    for index, session in enumerate(member.get("workout_history", [])):
        session_id = f"WorkoutSession:jordan_{_slug(str(session['date']))}_{index:02d}"
        span_id = _member_source_span(
            nodes,
            span_id=f"SourceSpan:assessment_workout_{index:02d}",
            json_path=f"$.workout_history[{index}]",
            value=session,
            source_hash=source_hash,
            timestamp=str(session.get("date")),
        )
        _add_unique_node(nodes, _node(session_id, "WorkoutSession", str(session["title"]), properties=session))
        edges.extend([_edge(member_id, "HAS_WORKOUT_SESSION", session_id), _edge(session_id, "DERIVED_FROM", span_id)])
        for ex_index, exercise_name in enumerate(session.get("exercises", [])):
            performance_id = f"ExercisePerformance:{_slug(str(session['date']))}_{ex_index:02d}"
            _add_unique_node(
                nodes,
                _node(
                    performance_id,
                    "ExercisePerformance",
                    str(exercise_name),
                    properties={"exercise_name": exercise_name, "session_date": session.get("date")},
                ),
            )
            edges.append(_edge(session_id, "HAS_EXERCISE_PERFORMANCE", performance_id))

    adherence = member.get("adherence", {})
    for index, observation in enumerate(adherence.get("weekly_completion_pct", [])):
        obs_id = f"AdherenceObservation:jordan_week_{_slug(str(observation['week_of']))}"
        span_id = _member_source_span(
            nodes,
            span_id=f"SourceSpan:assessment_adherence_{index:02d}",
            json_path=f"$.adherence.weekly_completion_pct[{index}]",
            value=observation,
            source_hash=source_hash,
        )
        pct = int(observation["pct"])
        _add_unique_node(
            nodes,
            _node(
                obs_id,
                "AdherenceObservation",
                f"Jordan adherence week of {observation['week_of']}",
                properties={
                    "week_start": observation["week_of"],
                    "pct": pct,
                    "planned_sessions": 4,
                    "completed_sessions": round((pct / 100) * 4),
                    "trend": adherence.get("trend"),
                },
            ),
        )
        edges.extend([_edge(member_id, "HAS_ADHERENCE_OBSERVATION", obs_id), _edge(obs_id, "DERIVED_FROM", span_id)])

    biomarkers = member.get("biomarkers", {})
    biomarker_span = _member_source_span(
        nodes,
        span_id="SourceSpan:assessment_biomarkers",
        json_path="$.biomarkers",
        value=biomarkers,
        source_hash=source_hash,
    )
    sleep_id = "BiomarkerObservation:jordan_sleep_last_7_days"
    _add_unique_node(
        nodes,
        _node(
            sleep_id,
            "BiomarkerObservation",
            "Jordan sleep last 7 days",
            aliases=["sleep this week"],
            properties={
                "metric": "sleep_hours",
                "period": "last_7_days",
                "period_end": "2026-06-04",
                "unit": "hours",
                "values": biomarkers.get("sleep_hours_last_7_days", []),
            },
        ),
    )
    edges.extend([_edge(member_id, "HAS_BIOMARKER_OBSERVATION", sleep_id), _edge(sleep_id, "DERIVED_FROM", biomarker_span)])
    for metric in ("resting_hr_bpm", "hrv_ms"):
        if metric in biomarkers:
            metric_id = f"BiomarkerObservation:jordan_{metric}"
            _add_unique_node(
                nodes,
                _node(metric_id, "BiomarkerObservation", metric, properties={"metric": metric, "value": biomarkers[metric]}),
            )
            edges.extend([_edge(member_id, "HAS_BIOMARKER_OBSERVATION", metric_id), _edge(metric_id, "DERIVED_FROM", biomarker_span)])
    for index, item in enumerate(biomarkers.get("weight_trend_kg", [])):
        weight_id = f"BiomarkerObservation:jordan_weight_{index:02d}"
        _add_unique_node(
            nodes,
            _node(weight_id, "BiomarkerObservation", f"Jordan weight {item['date']}", properties={"metric": "weight_kg", **item}),
        )
        edges.extend([_edge(member_id, "HAS_BIOMARKER_OBSERVATION", weight_id), _edge(weight_id, "DERIVED_FROM", biomarker_span)])

    labs = member.get("labs", {})
    for panel_name, panel in labs.items():
        panel_span = _member_source_span(
            nodes,
            span_id=f"SourceSpan:assessment_lab_{_slug(panel_name)}",
            json_path=f"$.labs.{panel_name}",
            value=panel,
            source_hash=source_hash,
            timestamp=str(panel.get("date")),
        )
        for metric, value in panel.items():
            if metric == "date":
                continue
            lab_id = f"LabResult:jordan_{_slug(panel_name)}_{_slug(metric)}"
            _add_unique_node(
                nodes,
                _node(
                    lab_id,
                    "LabResult",
                    metric.replace("_", " "),
                    properties={"panel": panel_name, "metric": metric, "value": value, "date": panel.get("date")},
                ),
            )
            edges.extend([_edge(member_id, "HAS_LAB_RESULT", lab_id), _edge(lab_id, "DERIVED_FROM", panel_span)])

    for index, message in enumerate(member.get("chat_history", [])):
        msg_id = f"Message:jordan_chat_{index:02d}"
        span_id = _member_source_span(
            nodes,
            span_id=f"SourceSpan:assessment_chat_{index:02d}",
            json_path=f"$.chat_history[{index}]",
            value=message,
            source_hash=source_hash,
            timestamp=str(message.get("ts")),
        )
        _add_unique_node(nodes, _node(msg_id, "Message", str(message.get("text", ""))[:80], properties=message))
        edges.extend([_edge(member_id, "HAS_MESSAGE", msg_id), _edge(msg_id, "DERIVED_FROM", span_id)])
        for attach_index, attachment in enumerate(message.get("attachments", [])):
            attachment_id = f"Attachment:jordan_chat_{index:02d}_{attach_index:02d}"
            _add_unique_node(nodes, _node(attachment_id, "Attachment", str(attachment.get("caption", "attachment")), properties=attachment))
            edges.append(_edge(msg_id, "HAS_ATTACHMENT", attachment_id))

    coach_brief = member.get("coach_brief", {})
    brief_span = _member_source_span(
        nodes,
        span_id="SourceSpan:assessment_coach_brief",
        json_path="$.coach_brief",
        value=coach_brief,
        source_hash=source_hash,
        timestamp=str(coach_brief.get("generated_for")),
    )
    brief_id = "CoachBrief:jordan_morning_assessment"
    brief_text = " ".join(task.get("text", "") for task in coach_brief.get("morning_tasks", []))
    _add_unique_node(
        nodes,
        _node(
            brief_id,
            "CoachBrief",
            f"Jordan coach brief {coach_brief.get('generated_for')}",
            aliases=["show me the brief", "morning brief"],
            properties={"generated_for": coach_brief.get("generated_for"), "text": brief_text},
        ),
    )
    edges.extend([_edge(member_id, "HAS_COACH_BRIEF", brief_id), _edge(brief_id, "DERIVED_FROM", brief_span)])
    for index, task in enumerate(coach_brief.get("morning_tasks", [])):
        task_id = f"CoachTask:jordan_morning_{index:02d}"
        _add_unique_node(nodes, _node(task_id, "CoachTask", str(task.get("text", "")), properties=task))
        edges.extend([_edge(brief_id, "HAS_COACH_TASK", task_id), _edge(task_id, "DERIVED_FROM", brief_span)])
    churn = coach_brief.get("churn_risk", {})
    churn_id = "ChurnSignal:jordan_assessment_churn_risk"
    _add_unique_node(
        nodes,
        _node(
            churn_id,
            "ChurnSignal",
            f"{churn.get('level', 'unknown')} churn risk",
            aliases=["churn risk"],
            properties={
                "risk_level": churn.get("level"),
                "observed_at": coach_brief.get("generated_for"),
                "reasons": churn.get("reasons", []),
                "model_scored": False,
            },
        ),
    )
    edges.extend([_edge(member_id, "HAS_CHURN_SIGNAL", churn_id), _edge(churn_id, "DERIVED_FROM", brief_span)])

    return {
        "schema_version": "0.1.0",
        "graph_version": "assessment-member-fixture-generated-v0",
        "status": "generated",
        "description": "Generated from the frozen candidate-assessment synthetic member fixture.",
        "source": {
            "path": MEMBER_CONTEXT_SOURCE_FILE,
            "sha256": source_hash,
            "source_snapshot_commit": SOURCE_SNAPSHOT_COMMIT,
        },
        "nodes": [nodes[node_id] for node_id in sorted(nodes)],
        "edges": sorted(edges, key=lambda edge: (edge["source"], edge["predicate"], edge["target"])),
    }


def _unique_count(exercises: list[dict[str, Any]], field: str) -> int:
    return len({str(value) for exercise in exercises for value in exercise.get(field, [])})


def _conformance_summary(
    exercises: list[dict[str, Any]],
    member: dict[str, Any],
    exercise_hash: str,
    member_hash: str,
    exercise_graph: dict[str, Any],
    member_graph: dict[str, Any],
) -> dict[str, Any]:
    exercise_nodes = [node for node in exercise_graph["nodes"] if node["type"] == "Exercise"]
    source_spans = [node for node in member_graph["nodes"] if node["type"] == "SourceSpan"]
    required_member_sections = (
        "profile",
        "goals",
        "preferences",
        "equipment_available",
        "injuries",
        "workout_history",
        "adherence",
        "biomarkers",
        "labs",
        "chat_history",
        "coach_brief",
    )
    represented_sections = set()
    for node in source_spans:
        json_path = str(node["properties"].get("json_path", ""))
        if not json_path.startswith("$."):
            continue
        represented_sections.add(json_path[2:].split(".", 1)[0].split("[", 1)[0])
    expected = {
        "exercise_count": 50,
        "muscle_group_count": 19,
        "loaded_body_region_count": 9,
        "movement_pattern_count": 36,
        "equipment_count": 32,
    }
    actual = {
        "exercise_count": len(exercises),
        "muscle_group_count": _unique_count(exercises, "muscle_groups"),
        "loaded_body_region_count": _unique_count(exercises, "joints_loaded"),
        "movement_pattern_count": _unique_count(exercises, "movement_patterns"),
        "equipment_count": _unique_count(exercises, "equipment_required"),
    }
    return {
        "status": "pass" if actual == expected and len(exercise_nodes) == len(exercises) else "fail",
        "expected_counts": expected,
        "actual_counts": actual,
        "exercise_source_sha256": exercise_hash,
        "member_source_sha256": member_hash,
        "source_snapshot_commit": SOURCE_SNAPSHOT_COMMIT,
        "generated_exercise_node_count": len(exercise_graph["nodes"]),
        "generated_exercise_edge_count": len(exercise_graph["edges"]),
        "generated_member_node_count": len(member_graph["nodes"]),
        "generated_member_edge_count": len(member_graph["edges"]),
        "member_sections_expected": list(required_member_sections),
        "member_sections_represented": sorted(represented_sections),
        "member_sections_missing": sorted(set(required_member_sections) - represented_sections),
        "all_exercise_records_preserved": all(
            "source_fields" in (node.get("properties") or {}) for node in exercise_nodes
        ),
        "synthetic_data_only": bool(member.get("_note", "").lower().startswith("synthetic")),
    }


def build_assessment_import_artifacts(
    *,
    exercises_path: Path = EXERCISES_PATH,
    member_context_path: Path = MEMBER_CONTEXT_PATH,
) -> AssessmentImportArtifacts:
    """Build generated graph payloads from the frozen assessment fixture files."""

    exercises = _load_json(exercises_path)
    member = _load_json(member_context_path)
    if not isinstance(exercises, list):
        raise ValueError("exercises.json must contain a list")
    if not isinstance(member, dict):
        raise ValueError("member-context.json must contain an object")

    exercise_hash = _sha256(exercises_path)
    member_hash = _sha256(member_context_path)
    exercise_graph = _build_exercise_graph(exercises, exercise_hash)
    member_graph = _build_member_graph(member, member_hash)
    conformance_summary = _conformance_summary(
        exercises,
        member,
        exercise_hash,
        member_hash,
        exercise_graph,
        member_graph,
    )
    return AssessmentImportArtifacts(
        exercise_graph=exercise_graph,
        member_graph=member_graph,
        conformance_summary=conformance_summary,
    )


def write_assessment_import_artifacts(
    output_dir: Path = GENERATED_DIR,
) -> dict[str, str]:
    """Write generated assessment graph snapshots and return path metadata."""

    artifacts = build_assessment_import_artifacts()
    output_dir.mkdir(parents=True, exist_ok=True)
    paths = {
        "exercise_graph": output_dir / "assessment_exercise_kg.generated.json",
        "member_graph": output_dir / "assessment_member_kg.generated.json",
        "conformance_summary": output_dir / "assessment_conformance_summary.json",
    }
    payloads = {
        "exercise_graph": artifacts.exercise_graph,
        "member_graph": artifacts.member_graph,
        "conformance_summary": artifacts.conformance_summary,
    }
    for key, path in paths.items():
        path.write_text(json.dumps(payloads[key], indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {key: str(path) for key, path in paths.items()}


def main() -> None:
    paths = write_assessment_import_artifacts()
    summary = build_assessment_import_artifacts().conformance_summary
    print(json.dumps({"written": paths, "conformance": summary}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
