window.FITGRAPH_DEMO = {
  meta: {
    runId: "demo-run-jordan-20260605-01",
    generatedAt: "2026-06-05T09:20:00-05:00",
    graphVersion: "fitgraph-kg-m5-validation-v0",
    rulesetVersion: "ruleset-m2-safety-v0",
    ontologyLockVersion: "ontology-lock-m0-unverified",
    fixtureMode: "static_dashboard_fixture",
    sourceSnapshot: "docs/external/candidate-assessment/data/member-context.json",
    exerciseSnapshot: "docs/external/candidate-assessment/data/exercises.json"
  },
  coach: {
    name: "Sam Patel",
    role: "1:1 Coach",
    queue: [
      { label: "Plan due", value: "Today" },
      { label: "Risk", value: "Elevated" },
      { label: "Last check-in", value: "Jun 3, 6:42 PM" }
    ]
  },
  member: {
    id: "mbr_01HX9JORDAN",
    graphId: "Member:jordan",
    name: "Jordan Rivera",
    age: 41,
    tier: "1:1 Coaching",
    timezone: "America/Los_Angeles",
    goals: [
      "Build lower-body strength",
      "Return to pain-free squatting after left-knee flare-up",
      "Average 7+ hours of sleep on weeknights"
    ],
    equipment: [
      "Dumbbell",
      "Kettlebell",
      "Yoga Mat",
      "Resistance Band - Loop",
      "Flat Bench"
    ],
    restrictions: [
      {
        label: "Active left-knee restriction",
        severity: "medical hard block",
        since: "2026-05-10",
        detail: "Cleared for low-impact loading; avoid deep knee flexion under load and plyometrics."
      }
    ],
    preferences: [
      "Prefers dumbbell and kettlebell work",
      "Trains at home",
      "Dislikes Deadlift",
      "Dislikes Burpees"
    ]
  },
  workoutRequest: {
    memberId: "mbr_01HX9JORDAN",
    prompt: "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB. Keep left knee low impact.",
    minutes: 50,
    constraints: [
      { type: "BodyRegion", value: "left knee", hard: true, source: "avoid deep knee flexion under load" },
      { type: "ExerciseFamily", value: "deadlift family", hard: true, negated: true, source: "Exclude deadlifts" },
      { type: "Equipment", value: "barbell", hard: true, negated: true, source: "Only DB and KB; no barbell" }
    ]
  },
  generation: {
    summary: {
      selectedCount: 5,
      filteredCount: 7,
      alternativesCount: 5,
      unresolvedCount: 0,
      safePoolCount: 18
    },
    selected: [
      {
        id: "Exercise:glute_bridge",
        label: "Glute Bridge",
        block: "Strength A",
        prescription: "4 x 10, 60 sec rest",
        focus: "Glutes, hamstrings",
        equipment: ["Yoga Mat"],
        receiptId: "dec-glute-bridge",
        reason: "Passed active left-knee, equipment, and prompt-exclusion checks."
      },
      {
        id: "Exercise:banded_lateral_walk",
        label: "Banded Lateral Walk",
        block: "Activation",
        prescription: "3 x 12 each side",
        focus: "Glute med, hip stability",
        equipment: ["Resistance Band - Loop"],
        receiptId: "dec-banded-walk",
        reason: "Low-impact accessory, available equipment, no deadlift-family match."
      },
      {
        id: "Exercise:hip_thrust",
        label: "Bench Hip Thrust",
        block: "Strength B",
        prescription: "3 x 8, tempo 2-1-2",
        focus: "Glutes",
        equipment: ["Flat Bench", "Yoga Mat"],
        receiptId: "dec-hip-thrust",
        reason: "Hip-dominant alternative that avoids loaded deep knee flexion."
      },
      {
        id: "Exercise:dumbbell_floor_press",
        label: "Dumbbell Floor Press",
        block: "Accessory Superset",
        prescription: "3 x 10",
        focus: "Chest, triceps",
        equipment: ["Dumbbell"],
        receiptId: "dec-db-floor-press",
        reason: "Upper accessory passed equipment and safety checks."
      },
      {
        id: "Exercise:tall_kneeling_pallof_press",
        label: "Tall-Kneeling Pallof Press",
        block: "Core Finish",
        prescription: "3 x 30 sec each side",
        focus: "Core anti-rotation",
        equipment: ["Resistance Band - Loop"],
        receiptId: "dec-pallof",
        reason: "Low-impact core work with no blocked equipment."
      }
    ],
    receipts: [
      {
        id: "dec-barbell-back-squat",
        exerciseId: "Exercise:barbell_back_squat",
        label: "Barbell Back Squat",
        decision: "filtered",
        primarySeverity: "MEDICAL_HARD_BLOCK",
        primaryReasonCode: "ACTIVE_KNEE_RESTRICTION",
        reasonCodes: ["ACTIVE_KNEE_RESTRICTION", "MISSING_EQUIPMENT:barbell", "DISALLOWED_EQUIPMENT:barbell"],
        graphPaths: [
          "Exercise:barbell_back_squat -STRESSES-> BodyRegion:left_knee",
          "SafetyRule:avoid_loaded_knee_flexion -USES_CONCEPT-> BodyRegion:knee",
          "Exercise:barbell_back_squat -REQUIRES-> Equipment:barbell"
        ],
        sourceIds: ["src-injury", "src-equipment", "src-prompt"],
        fingerprint: "d8b52ca3912e7a08"
      },
      {
        id: "dec-goblet-squat",
        exerciseId: "Exercise:goblet_squat",
        label: "Goblet Squat",
        decision: "filtered",
        primarySeverity: "MEDICAL_HARD_BLOCK",
        primaryReasonCode: "ACTIVE_KNEE_RESTRICTION",
        reasonCodes: ["ACTIVE_KNEE_RESTRICTION"],
        graphPaths: [
          "Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee",
          "SafetyRule:avoid_loaded_knee_flexion -USES_CONCEPT-> BodyRegion:knee"
        ],
        sourceIds: ["src-injury", "src-prompt"],
        fingerprint: "dce662dc652041da"
      },
      {
        id: "dec-jump-squat",
        exerciseId: "Exercise:jump_squat",
        label: "Jump Squat",
        decision: "filtered",
        primarySeverity: "MEDICAL_HARD_BLOCK",
        primaryReasonCode: "ACTIVE_KNEE_HIGH_IMPACT_RESTRICTION",
        reasonCodes: ["ACTIVE_KNEE_HIGH_IMPACT_RESTRICTION"],
        graphPaths: [
          "Exercise:jump_squat -STRESSES-> BodyRegion:left_knee",
          "SafetyRule:avoid_high_impact_knee_stress -USES_CONCEPT-> BodyRegion:knee"
        ],
        sourceIds: ["src-injury"],
        fingerprint: "f1be579a5c987aeb"
      },
      {
        id: "dec-kb-deadlift",
        exerciseId: "Exercise:kettlebell_deadlift",
        label: "Kettlebell Deadlift",
        decision: "filtered",
        primarySeverity: "PROMPT_EXCLUSION",
        primaryReasonCode: "PROMPT_EXCLUDED_FAMILY:deadlift_family",
        reasonCodes: ["PROMPT_EXCLUDED_FAMILY:deadlift_family"],
        graphPaths: ["Exercise:kettlebell_deadlift -VARIANT_OF-> ExerciseFamily:deadlift_family"],
        sourceIds: ["src-prompt", "src-preferences"],
        fingerprint: "a278a0b7b79ee081"
      },
      {
        id: "dec-barbell-bench",
        exerciseId: "Exercise:barbell_bench_press",
        label: "Barbell Bench Press",
        decision: "filtered",
        primarySeverity: "EQUIPMENT_HARD_BLOCK",
        primaryReasonCode: "MISSING_EQUIPMENT:barbell",
        reasonCodes: ["MISSING_EQUIPMENT:barbell", "DISALLOWED_EQUIPMENT:barbell"],
        graphPaths: ["Exercise:barbell_bench_press -REQUIRES-> Equipment:barbell"],
        sourceIds: ["src-equipment", "src-prompt"],
        fingerprint: "7bf2f9787a92d6e2"
      },
      {
        id: "dec-glute-bridge",
        exerciseId: "Exercise:glute_bridge",
        label: "Glute Bridge",
        decision: "selected",
        primarySeverity: "BOOST",
        primaryReasonCode: "PASSED_SAFETY",
        reasonCodes: ["PASSED_SAFETY"],
        graphPaths: [
          "Exercise:glute_bridge -REQUIRES-> Equipment:yoga_mat",
          "Exercise:glute_bridge -STRESSES-> BodyRegion:hip",
          "Exercise:glute_bridge -TARGETS-> MuscleGroup:glutes"
        ],
        sourceIds: ["src-equipment", "src-injury"],
        fingerprint: "27ba04bf3f4f6732"
      },
      {
        id: "dec-db-floor-press",
        exerciseId: "Exercise:dumbbell_floor_press",
        label: "Dumbbell Floor Press",
        decision: "selected",
        primarySeverity: "BOOST",
        primaryReasonCode: "PASSED_SAFETY",
        reasonCodes: ["PASSED_SAFETY"],
        graphPaths: [
          "Exercise:dumbbell_floor_press -REQUIRES-> Equipment:dumbbell",
          "Exercise:dumbbell_floor_press -HAS_PATTERN-> MovementPattern:horizontal_press"
        ],
        sourceIds: ["src-equipment"],
        fingerprint: "99c7799b9113a7e4"
      },
      {
        id: "dec-banded-walk",
        exerciseId: "Exercise:banded_lateral_walk",
        label: "Banded Lateral Walk",
        decision: "selected",
        primarySeverity: "BOOST",
        primaryReasonCode: "PASSED_SAFETY",
        reasonCodes: ["PASSED_SAFETY", "GOAL_ALIGNMENT:hip_stability"],
        graphPaths: [
          "Exercise:banded_lateral_walk -REQUIRES-> Equipment:resistance_band_loop",
          "Exercise:banded_lateral_walk -TARGETS-> MuscleGroup:glute_med"
        ],
        sourceIds: ["src-equipment", "src-goals"],
        fingerprint: "fixture-band-walk"
      },
      {
        id: "dec-hip-thrust",
        exerciseId: "Exercise:hip_thrust",
        label: "Bench Hip Thrust",
        decision: "selected",
        primarySeverity: "BOOST",
        primaryReasonCode: "PASSED_SAFETY",
        reasonCodes: ["PASSED_SAFETY", "GOAL_ALIGNMENT:lower_body_strength"],
        graphPaths: [
          "Exercise:hip_thrust -REQUIRES-> Equipment:flat_bench",
          "Exercise:hip_thrust -STRESSES-> BodyRegion:hip",
          "Exercise:hip_thrust -TARGETS-> MuscleGroup:glutes"
        ],
        sourceIds: ["src-equipment", "src-goals"],
        fingerprint: "fixture-hip-thrust"
      },
      {
        id: "dec-pallof",
        exerciseId: "Exercise:tall_kneeling_pallof_press",
        label: "Tall-Kneeling Pallof Press",
        decision: "selected",
        primarySeverity: "BOOST",
        primaryReasonCode: "PASSED_SAFETY",
        reasonCodes: ["PASSED_SAFETY", "LOW_IMPACT_CORE"],
        graphPaths: [
          "Exercise:tall_kneeling_pallof_press -REQUIRES-> Equipment:resistance_band_loop",
          "Exercise:tall_kneeling_pallof_press -HAS_PATTERN-> MovementPattern:core_anti_rotation"
        ],
        sourceIds: ["src-equipment", "src-injury"],
        fingerprint: "fixture-pallof"
      }
    ],
    alternatives: [
      {
        filtered: "Barbell Back Squat",
        alternative: "Glute Bridge",
        score: 0.34,
        reason: "Shares glute target and avoids loaded deep knee flexion.",
        graphPaths: [
          "Exercise:barbell_back_squat -TARGETS-> MuscleGroup:glutes",
          "Exercise:glute_bridge -TARGETS-> MuscleGroup:glutes",
          "Exercise:glute_bridge -REQUIRES-> Equipment:yoga_mat"
        ]
      },
      {
        filtered: "Goblet Squat",
        alternative: "Bench Hip Thrust",
        score: 0.72,
        reason: "Keeps lower-body strength goal with hip-dominant loading.",
        graphPaths: [
          "Exercise:goblet_squat -TARGETS-> MuscleGroup:glutes",
          "Exercise:hip_thrust -TARGETS-> MuscleGroup:glutes",
          "Exercise:hip_thrust -STRESSES-> BodyRegion:hip"
        ]
      },
      {
        filtered: "Jump Squat",
        alternative: "Banded Lateral Walk",
        score: 0.61,
        reason: "Removes high impact while retaining hip stability work.",
        graphPaths: [
          "Exercise:jump_squat -HAS_PATTERN-> MovementPattern:plyometric",
          "Exercise:banded_lateral_walk -REQUIRES-> Equipment:resistance_band_loop"
        ]
      },
      {
        filtered: "Kettlebell Deadlift",
        alternative: "Glute Bridge",
        score: 0.99,
        reason: "Same posterior-chain intent, selected from safe pool only.",
        graphPaths: [
          "Exercise:kettlebell_deadlift -VARIANT_OF-> ExerciseFamily:deadlift_family",
          "Exercise:glute_bridge -HAS_PATTERN-> MovementPattern:hip_hinge"
        ]
      },
      {
        filtered: "Barbell Bench Press",
        alternative: "Dumbbell Floor Press",
        score: 0.965,
        reason: "Same horizontal press pattern with available dumbbells.",
        graphPaths: [
          "Exercise:barbell_bench_press -HAS_PATTERN-> MovementPattern:horizontal_press",
          "Exercise:dumbbell_floor_press -REQUIRES-> Equipment:dumbbell"
        ]
      }
    ]
  },
  charts: {
    adherence: [
      { label: "May 12", value: 100 },
      { label: "May 19", value: 100 },
      { label: "May 26", value: 75 },
      { label: "Jun 2", value: 50 }
    ],
    sleep: [
      { label: "Thu", value: 6.1 },
      { label: "Fri", value: 5.4 },
      { label: "Sat", value: 7.2 },
      { label: "Sun", value: 6.0 },
      { label: "Mon", value: 5.1 },
      { label: "Tue", value: 7.8 },
      { label: "Wed", value: 6.3 }
    ],
    messages: [
      { label: "May 13", member: 4, coach: 3 },
      { label: "May 20", member: 3, coach: 3 },
      { label: "May 27", member: 2, coach: 2 },
      { label: "Jun 3", member: 1, coach: 2 }
    ]
  },
  copilot: {
    prompts: [
      "Morning coach brief",
      "Adherence trend",
      "Sleep this week",
      "Churn risk",
      "Message pattern",
      "Last-four-weeks comparison"
    ],
    responses: {
      "Morning coach brief": {
        answer: "Congratulate Jordan on the pain-free lower-body session, keep the next plan low impact, and check the recent adherence drop before assigning more volume.",
        cards: [
          {
            claim: "Jordan completed the Jun 3 lower-body session and reported the knee felt okay with box squats.",
            confidence: "deterministic",
            query: "member_retrieval.coach_brief",
            sourceIds: ["src-workout-jun3", "src-message-jun3"]
          },
          {
            claim: "Adherence declined from 100% to 50% across the latest graph observations.",
            confidence: "deterministic",
            query: "member_retrieval.adherence_trend",
            sourceIds: ["src-adherence"]
          }
        ]
      },
      "Adherence trend": {
        answer: "Adherence is declining: the graph shows 100%, 100%, 75%, then 50% weekly completion. Treat the next assignment as friction-reducing rather than volume-increasing.",
        cards: [
          {
            claim: "Weekly adherence moved from 100% on 2026-05-12 to 50% on 2026-06-02.",
            confidence: "deterministic",
            query: "member_retrieval.adherence_trend",
            sourceIds: ["src-adherence"]
          }
        ]
      },
      "Sleep this week": {
        answer: "Sleep averaged 6.3 hours across the last seven nights, below the 7-hour goal. Keep intensity moderate and ask about weekday wind-down barriers.",
        cards: [
          {
            claim: "Sleep observations for the last seven days average 6.3 hours.",
            confidence: "deterministic",
            query: "member_retrieval.sleep_this_week",
            sourceIds: ["src-sleep"]
          }
        ]
      },
      "Churn risk": {
        answer: "Churn risk is elevated because adherence fell, one missed workout was tied to fatigue and work, and login frequency is down versus the prior month.",
        cards: [
          {
            claim: "Jordan has elevated churn risk: adherence fell, one skipped session cited fatigue/work, and login frequency is down.",
            confidence: "deterministic",
            query: "member_retrieval.churn_risk",
            sourceIds: ["src-coach-brief", "src-message-may30"]
          }
        ]
      },
      "Message pattern": {
        answer: "Member messages are tapering week over week while coach touches remain steady. The next message should ask one low-friction recovery question.",
        cards: [
          {
            claim: "Member outbound messages decreased from 4 to 1 across the four displayed weeks.",
            confidence: "deterministic",
            query: "member_retrieval.message_pattern",
            sourceIds: ["src-chat-history"]
          }
        ]
      },
      "Last-four-weeks comparison": {
        answer: "The last four weeks moved from full completion to half completion while sleep stayed below goal on most weekdays. No graph-backed lab change is needed for this plan.",
        cards: [
          {
            claim: "Adherence observations are 100%, 100%, 75%, and 50% for the last four graph weeks.",
            confidence: "deterministic",
            query: "member_retrieval.last_four_weeks",
            sourceIds: ["src-adherence"]
          },
          {
            claim: "The graph has no supporting fact for a new lab-driven exercise restriction after 2026-04-20.",
            confidence: "deterministic",
            query: "member_retrieval.lab_restriction_check",
            sourceIds: []
          }
        ]
      }
    }
  },
  sources: {
    "src-prompt": {
      title: "Coach prompt",
      path: "dashboard fixture",
      jsonPath: "$.workoutRequest.prompt",
      excerpt: "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB."
    },
    "src-injury": {
      title: "Injury episode",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.injuries[0]",
      excerpt: "Cleared for low-impact loading; avoid deep knee flexion under load and plyometrics."
    },
    "src-equipment": {
      title: "Available equipment",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.equipment_available",
      excerpt: "Dumbbell, Kettlebell, Yoga Mat, Resistance Band - Loop, Flat Bench"
    },
    "src-preferences": {
      title: "Member preferences",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.preferences",
      excerpt: "Prefers dumbbell and kettlebell work; trains at home. Dislikes Deadlift and Burpees."
    },
    "src-goals": {
      title: "Member goals",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.goals",
      excerpt: "Build lower-body strength; return to pain-free squatting."
    },
    "src-adherence": {
      title: "Adherence observations",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.adherence.weekly_completion_pct",
      excerpt: "100, 100, 75, 50"
    },
    "src-sleep": {
      title: "Sleep biomarker observations",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.biomarkers.sleep_hours_last_7_days",
      excerpt: "6.1, 5.4, 7.2, 6.0, 5.1, 7.8, 6.3"
    },
    "src-chat-history": {
      title: "Chat history",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.chat_history",
      excerpt: "Latest member and coach messages around missed sessions, home equipment, and knee response."
    },
    "src-message-jun3": {
      title: "Jun 3 member message",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.chat_history[0]",
      excerpt: "Knocked out the lower body session! Knee felt okay with the box squats."
    },
    "src-message-may30": {
      title: "May 30 skipped-session message",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.chat_history[2]",
      excerpt: "Skipped Thursday, work blew up and I was wiped."
    },
    "src-workout-jun3": {
      title: "Jun 3 workout history",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.workout_history[0]",
      excerpt: "Lower Body - Bands & DB completed, 28 min, RPE 6."
    },
    "src-coach-brief": {
      title: "Coach brief",
      path: "docs/external/candidate-assessment/data/member-context.json",
      jsonPath: "$.coach_brief",
      excerpt: "Review churn risk: adherence dropped 100% to 50% over the last two weeks."
    }
  }
};
