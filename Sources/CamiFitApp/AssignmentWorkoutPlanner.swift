import Foundation
import KGKit

protocol AssignmentWorkoutPlanning: AnyObject {
    func makeArtifact(prompt: String) throws -> KGWorkoutChatArtifact
    func makeArtifact(request: KGWorkoutPlanningRequest) throws -> KGWorkoutChatArtifact
}

struct KGWorkoutPlanningRequest: Equatable {
    let prompt: String
    let minutes: Int?
    let reason: String?

    init(prompt: String, minutes: Int? = nil, reason: String? = nil) {
        self.prompt = prompt
        self.minutes = minutes
        self.reason = reason
    }
}

enum KGWorkoutRequestParser {
    private static let requestFenceTags = [
        "future-workout-plan"
    ]

    static func parse(message: String) -> [KGWorkoutPlanningRequest] {
        fencedBlocks(in: message).compactMap(decodeRequest)
    }

    private static func fencedBlocks(in message: String) -> [String] {
        var blocks: [String] = []
        var isCapturing = false
        var current: [String] = []

        for line in message.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isCapturing {
                if trimmed == "```" {
                    blocks.append(current.joined(separator: "\n"))
                    current = []
                    isCapturing = false
                } else {
                    current.append(line)
                }
            } else if isRequestFence(trimmed) {
                isCapturing = true
            }
        }

        return blocks
    }

    private static func isRequestFence(_ trimmedLine: String) -> Bool {
        let lowercased = trimmedLine.lowercased()
        return requestFenceTags.contains { lowercased == "```\($0)" }
    }

    private static func decodeRequest(_ text: String) -> KGWorkoutPlanningRequest? {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawRequest.self, from: data),
              raw.schemaVersion == 1,
              raw.tool == "generate_workout",
              let prompt = cleaned(raw.prompt) else {
            return nil
        }

        return KGWorkoutPlanningRequest(
            prompt: prompt,
            minutes: validMinutes(raw.minutes),
            reason: cleaned(raw.reason)
        )
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func validMinutes(_ minutes: Int?) -> Int? {
        guard let minutes, (5...180).contains(minutes) else { return nil }
        return minutes
    }

    private struct RawRequest: Decodable {
        let schemaVersion: Int
        let tool: String
        let prompt: String?
        let minutes: Int?
        let reason: String?
    }
}

struct KGWorkoutDecisionEvidence: Identifiable, Equatable {
    var id: String { exerciseID }
    let exerciseID: String
    let name: String
    let decision: String
    let reasonCodes: [String]
    let primaryReasonCode: String
    let primarySeverity: String
    let graphPaths: [String]
}

struct KGWorkoutAlternativeEvidence: Identifiable, Equatable {
    var id: String { "\(filteredExerciseID)->\(alternativeExerciseID)" }
    let filteredExerciseID: String
    let alternativeExerciseID: String
    let score: Double
    let graphPaths: [String]
}

struct KGWorkoutPresetMapping: Identifiable, Equatable {
    var id: String { kgExerciseID }
    let kgExerciseID: String
    let kgExerciseName: String
    let presetID: String
    let readinessStatus: String
    let reason: String
}

struct KGWorkoutMemoryReference: Identifiable, Equatable {
    var id: String { operationID }
    let operationID: String
    let title: String
    let sourceText: String
}

struct KGWorkoutChatArtifact: Identifiable, Equatable {
    let id: String
    let plan: WorkoutPlan
    let routine: WorkoutRoutine
    let selected: [KGWorkoutDecisionEvidence]
    let filtered: [KGWorkoutDecisionEvidence]
    let alternatives: [KGWorkoutAlternativeEvidence]
    let presetMappings: [KGWorkoutPresetMapping]
    let recommendOnlySelected: [KGWorkoutDecisionEvidence]
    let overlayConstraintCount: Int
    let memoryReferences: [KGWorkoutMemoryReference]

    var summaryText: String {
        "Generated a routine using your saved context. \(filtered.count) exercises were ruled out before the runnable card was built."
    }
}

final class AssignmentWorkoutPlanner: AssignmentWorkoutPlanning {
    private let applicationSupportDirectory: URL
    private let fileManager: FileManager
    private let baseArtifactData: () throws -> Data
    private let memberGraphData: () throws -> Data
    private let memberID: String
    private let availableEquipmentOverride: [String]?

    init(applicationSupportDirectory: URL? = nil,
         fileManager: FileManager = .default,
         baseArtifactData: @escaping () throws -> Data = { try ArtifactLoader.assessmentBundledData() },
         memberGraphData: @escaping () throws -> Data = { try ArtifactLoader.assessmentMemberGraphData() },
         memberID: String = "Member:jordan",
         availableEquipment: [String]? = nil) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? (try? KGWorkspace.applicationSupportDirectory(fileManager: fileManager))
            ?? fileManager.temporaryDirectory
        self.baseArtifactData = baseArtifactData
        self.memberGraphData = memberGraphData
        self.memberID = memberID
        self.availableEquipmentOverride = availableEquipment
    }

    func makeArtifact(prompt: String) throws -> KGWorkoutChatArtifact {
        try makeArtifact(request: KGWorkoutPlanningRequest(
            prompt: prompt,
            minutes: Self.minutes(in: prompt)
        ))
    }

    func makeArtifact(request: KGWorkoutPlanningRequest) throws -> KGWorkoutChatArtifact {
        let workspace = try KGWorkspace.prepare(
            applicationSupportDirectory: applicationSupportDirectory,
            baseArtifactData: try baseArtifactData(),
            fileManager: fileManager
        )
        let view = try MergedGraphView(workspace: workspace)
        let engine = SafetyEngine(graph: view.graph, rules: view.baseArtifact.safetyRules)
        let memberContext = try AssignmentMemberContext(data: memberGraphData())
        let promptEquipment = try Self.allowedEquipmentOnlyConstraints(prompt: request.prompt, graph: view.graph)
            .map(\.nodeID)
            .sorted()
        let memberEquipment = memberContext.availableEquipmentIDs(memberID: memberID, graph: view.graph)
        let availableEquipment = availableEquipmentOverride ?? (promptEquipment.isEmpty ? memberEquipment : promptEquipment)
        let overlayConstraints = view.overlay.activeConstraints
        let injuryConstraints = overlayConstraints.isEmpty
            ? try memberContext.activeInjuryConstraints(memberID: memberID, graph: view.graph)
            : []
        let memberConstraints = injuryConstraints + view.activeResolvedConstraints
        let minutes = request.minutes ?? Self.minutes(in: request.prompt) ?? 50
        let plan = try WorkoutGenerator.generateWorkout(
            engine: engine,
            prompt: request.prompt,
            minutes: minutes,
            availableEquipment: availableEquipment,
            memberConstraints: memberConstraints,
            memberID: memberID
        )
        let projection = KGWorkoutRoutineProjector(
            graph: view.graph,
            blockedPresetIDs: KGWorkoutRoutineProjector.blockedPresetIDs(for: memberConstraints)
        ).project(plan: plan)
        return KGWorkoutChatArtifact(
            id: projection.routine.id,
            plan: plan,
            routine: projection.routine,
            selected: plan.selectedExercises.map(KGWorkoutDecisionEvidence.init(summary:)),
            filtered: plan.filteredExercises.map(KGWorkoutDecisionEvidence.init(summary:)),
            alternatives: plan.alternatives.map(KGWorkoutAlternativeEvidence.init(summary:)),
            presetMappings: projection.mappings,
            recommendOnlySelected: projection.recommendOnly,
            overlayConstraintCount: overlayConstraints.count,
            memoryReferences: overlayConstraints.map(KGWorkoutMemoryReference.init(constraint:))
        )
    }

    static func isWorkoutRequest(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        let nouns = ["workout", "routine", "session", "plan", "warm-up", "warmup"]
        let verbs = ["make", "build", "create", "generate", "give", "plan", "program"]
        return nouns.contains { normalized.contains($0) } && verbs.contains { normalized.contains($0) }
    }

    static func minutes(in prompt: String) -> Int? {
        let pattern = #"(\d{1,3})\s*(?:-| )?\s*(?:minute|minutes|min)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
        guard let match = regex.firstMatch(in: prompt, range: range),
              let valueRange = Range(match.range(at: 1), in: prompt) else { return nil }
        return Int(prompt[valueRange])
    }

    static func allowedEquipmentOnlyConstraints(prompt: String, graph: LocalGraph) throws -> [ResolvedConstraint] {
        try Resolver.resolveText(prompt, graph: graph).filter {
            $0.constraintType == "Equipment"
                && $0.hard
                && $0.safetyBehavior == "allowed_equipment_only"
        }
    }
}

private struct AssignmentMemberContext {
    let nodes: [String: [String: Any]]
    let edges: [[String: Any]]

    init(data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let nodeList = root?["nodes"] as? [[String: Any]] ?? []
        self.nodes = Dictionary(uniqueKeysWithValues: nodeList.compactMap { node in
            guard let id = node["id"] as? String else { return nil }
            return (id, node)
        })
        self.edges = root?["edges"] as? [[String: Any]] ?? []
    }

    func availableEquipmentIDs(memberID: String, graph: LocalGraph) -> [String] {
        orderedTargets(from: memberID, predicate: "HAS_EQUIPMENT_AVAILABILITY")
            .flatMap { target -> [String] in
                guard let node = nodes[target],
                      node["type"] as? String == "EquipmentAvailability",
                      let properties = props(node) else { return [] }
                let equipmentIDs = (properties["equipment_ids"] as? [String] ?? [])
                    .filter { graph.nodes[$0]?.type == "Equipment" }
                if !equipmentIDs.isEmpty { return equipmentIDs }
                return (properties["equipment_labels"] as? [String] ?? [])
                    .map { NodeID.make("Equipment", $0) }
                    .filter { graph.nodes[$0]?.type == "Equipment" }
            }
            .deduplicated()
    }

    func activeInjuryConstraints(memberID: String, graph: LocalGraph) throws -> [ResolvedConstraint] {
        try orderedTargets(from: memberID, predicate: "HAS_INJURY").compactMap { target in
            guard let node = nodes[target],
                  let properties = props(node),
                  properties["status"] as? String == "active",
                  let regionID = properties["region_id"] as? String,
                  graph.nodes[regionID] != nil else {
                return nil
            }

            let regionValue = nodeValue(regionID)
            let graphPaths = graph.outgoing(regionID, predicate: "PART_OF").map { $0.path() }
            let laterality = laterality(for: regionID, graph: graph)
            return ResolvedConstraint(
                constraintType: "BodyRegion",
                value: regionValue,
                hard: true,
                sourceText: "\(node["label"] as? String ?? regionValue) active injury",
                graphPaths: graphPaths.isEmpty ? (try graph.partOfClosurePaths(regionID)) : graphPaths,
                laterality: laterality,
                safetyBehavior: "block_if_safety_critical"
            )
        }
    }

    private func orderedTargets(from source: String, predicate: String) -> [String] {
        edges.compactMap { edge in
            guard edge["source"] as? String == source,
                  edge["predicate"] as? String == predicate,
                  let target = edge["target"] as? String else { return nil }
            return target
        }.sorted()
    }

    private func props(_ node: [String: Any]?) -> [String: Any]? {
        node?["properties"] as? [String: Any]
    }

    private func nodeValue(_ nodeID: String) -> String {
        String(nodeID.split(separator: ":", maxSplits: 1).last ?? "")
    }

    private func laterality(for regionID: String, graph: LocalGraph) -> String? {
        guard let node = graph.nodes[regionID],
              case let .string(value)? = node.properties["laterality"],
              value != "neutral" else { return nil }
        return value
    }
}

private extension Array where Element == String {
    func deduplicated() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

private struct KGWorkoutRoutineProjector {
    let graph: LocalGraph
    let blockedPresetIDs: Set<String>

    func project(plan: WorkoutPlan) -> (
        routine: WorkoutRoutine,
        mappings: [KGWorkoutPresetMapping],
        recommendOnly: [KGWorkoutDecisionEvidence]
    ) {
        var mappings: [KGWorkoutPresetMapping] = []
        var blocks: [RoutineBlock] = []
        var usedPresetIDs: Set<String> = []
        var representedKGIDs: Set<String> = []
        let prescriptions = plan.warmup + plan.main + plan.cooldown

        for prescription in prescriptions {
            guard let mapping = mapping(for: prescription.exerciseID) else {
                blocks.append(catalogOnlyBlock(for: prescription))
                representedKGIDs.insert(prescription.exerciseID)
                continue
            }
            guard !usedPresetIDs.contains(mapping.presetID) else { continue }
            usedPresetIDs.insert(mapping.presetID)
            representedKGIDs.insert(mapping.kgExerciseID)
            mappings.append(mapping)
            blocks.append(block(for: prescription, presetID: mapping.presetID))
        }

        for summary in plan.selectedExercises where !representedKGIDs.contains(summary.exerciseID) {
            let prescription = WorkoutGenerator.prescription(graph, summary.exerciseID, "main")
            if let mapping = mapping(for: summary.exerciseID),
               !usedPresetIDs.contains(mapping.presetID) {
                usedPresetIDs.insert(mapping.presetID)
                representedKGIDs.insert(mapping.kgExerciseID)
                mappings.append(mapping)
                blocks.append(block(for: prescription, presetID: mapping.presetID))
            } else {
                blocks.append(catalogOnlyBlock(for: prescription))
                representedKGIDs.insert(summary.exerciseID)
            }
        }

        if Self.isLowerBodyRequest(plan.prompt), !Self.hasLowerBodyBlockingConstraint(plan.resolvedConstraints) {
            prioritizeLowerBodyPair(blocks: &blocks, mappings: &mappings)
        }

        if blocks.isEmpty {
            blocks = [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_squat"), sets: 1, reps: 8, restSeconds: 60)
            ]
            mappings = [
                KGWorkoutPresetMapping(
                    kgExerciseID: "fallback:bodyweight_squat",
                    kgExerciseName: "Bodyweight Squat",
                    presetID: "bodyweight_squat",
                    readinessStatus: "procedural_fallback",
                    reason: "No selected KG exercise mapped to a packaged app preset."
                )
            ]
        }

        let mappedKGIDs = Set(mappings.map(\.kgExerciseID))
        let recommendOnly = plan.selectedExercises
            .filter { !mappedKGIDs.contains($0.exerciseID) }
            .map(KGWorkoutDecisionEvidence.init(summary:))

        return (
            WorkoutRoutine(
                id: Self.routineID(prompt: plan.prompt),
                name: "\(plan.timeWindowMinutes)-Minute Workout",
                description: "Generated using your saved context, equipment, and safety constraints.",
                blocks: blocks
            ),
            mappings,
            recommendOnly
        )
    }

    private func block(for prescription: Prescription, presetID: String) -> RoutineBlock {
        if Self.timedHoldPresetIDs.contains(presetID) {
            return RoutineBlock(
                exerciseRef: .preset(id: presetID),
                sets: max(1, prescription.sets ?? 1),
                holdSeconds: Double(prescription.durationSeconds ?? 30),
                restSeconds: prescription.restSeconds
            )
        }

        return RoutineBlock(
            exerciseRef: .preset(id: presetID),
            sets: max(1, prescription.sets ?? 1),
            reps: lowerBoundReps(prescription.reps),
            holdSeconds: prescription.durationSeconds.map(Double.init),
            restSeconds: prescription.restSeconds
        )
    }

    private func catalogOnlyBlock(for prescription: Prescription) -> RoutineBlock {
        let coverage = AssignmentExerciseTrackingCoverage.coverage(forExerciseID: prescription.exerciseID, in: graph)
        return RoutineBlock(
            exerciseRef: .catalog(id: prescription.exerciseID, name: label(prescription.exerciseID)),
            sets: max(1, prescription.sets ?? 1),
            reps: lowerBoundReps(prescription.reps),
            holdSeconds: prescription.durationSeconds.map(Double.init),
            restSeconds: prescription.restSeconds,
            guidance: RoutineBlockGuidance(
                status: coverage.status.rawValue,
                displayText: catalogGuidanceDisplayText(for: coverage),
                note: catalogGuidanceNote(for: coverage),
                mappedPresetID: coverage.mappedPresetID
            )
        )
    }

    private func lowerBoundReps(_ reps: String?) -> Int? {
        guard let reps else { return nil }
        let digits = reps.prefix { $0.isNumber }
        return Int(digits)
    }

    private func mapping(for exerciseID: String) -> KGWorkoutPresetMapping? {
        let coverage = AssignmentExerciseTrackingCoverage.coverage(forExerciseID: exerciseID, in: graph)
        guard coverage.status == .guideReady,
              let presetID = coverage.mappedPresetID else { return nil }
        guard !blockedPresetIDs.contains(presetID) else { return nil }
        return KGWorkoutPresetMapping(
            kgExerciseID: exerciseID,
            kgExerciseName: self.label(exerciseID),
            presetID: presetID,
            readinessStatus: coverage.status.rawValue,
            reason: mappingReason(for: coverage)
        )
    }

    private func mappingReason(for coverage: ExerciseTrackingCoverage) -> String {
        switch coverage.status {
        case .guideReady:
            return "KG exercise maps exactly to a packaged guide-ready preset."
        case .archetypeDemoOnly:
            return "Mapped by KG exercise family or label to a packaged app preset; the exact KG exercise remains recommendation-only for measurement."
        case .recommendOnly:
            return "No packaged tracking data is available for this KG exercise."
        }
    }

    private func catalogGuidanceDisplayText(for coverage: ExerciseTrackingCoverage) -> String {
        switch coverage.status {
        case .guideReady:
            return "Guide represented"
        case .archetypeDemoOnly:
            return "No exact guide yet"
        case .recommendOnly:
            return "No guide yet"
        }
    }

    private func catalogGuidanceNote(for coverage: ExerciseTrackingCoverage) -> String {
        switch coverage.status {
        case .guideReady:
            return "This exercise is recommended, but its guide is already represented elsewhere in the generated routine."
        case .archetypeDemoOnly:
            return "Recommended by the KG, but the exact exercise guide is not packaged yet."
        case .recommendOnly:
            break
        }
        if coverage.reasons.contains("pending_licensed_reference_clip") {
            return "Recommended by the KG, but the guide is disabled until an accepted motion reference is captured."
        }
        return "Recommended by the KG, but no guide or tracking motion data is packaged yet."
    }

    private func label(_ exerciseID: String) -> String {
        graph.nodes[exerciseID]?.label ?? exerciseID
    }

    private static let timedHoldPresetIDs: Set<String> = [
        "bodyweight_plank"
    ]

    static func blockedPresetIDs(for constraints: [ResolvedConstraint]) -> Set<String> {
        let activeRegions = Set(constraints
            .filter { $0.constraintType == "BodyRegion" && $0.hard && !$0.negated }
            .map(\.nodeID))
        var blocked: Set<String> = []
        if !activeRegions.isDisjoint(with: upperBodyWeightBearingRegions) {
            blocked.formUnion(["bodyweight_plank", "bodyweight_pushup", "bodyweight_pike"])
        }
        return blocked
    }

    private static let upperBodyWeightBearingRegions: Set<String> = [
        "BodyRegion:wrist",
        "BodyRegion:shoulder",
        "BodyRegion:elbow",
        "BodyRegion:forearm"
    ]

    private static let lowerBodyConstraintRegions: Set<String> = [
        "BodyRegion:knee",
        "BodyRegion:left_knee",
        "BodyRegion:right_knee",
        "BodyRegion:hip",
        "BodyRegion:ankle",
        "BodyRegion:lower_back",
        "BodyRegion:lumbar_spine"
    ]

    private static func isLowerBodyRequest(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        return normalized.contains("lower") || normalized.contains("leg") || normalized.contains("lunge") || normalized.contains("squat")
    }

    private static func hasLowerBodyBlockingConstraint(_ constraints: [ResolvedConstraint]) -> Bool {
        let activeRegions = Set(constraints
            .filter { $0.constraintType == "BodyRegion" && $0.hard && !$0.negated }
            .map(\.nodeID))
        return !activeRegions.isDisjoint(with: lowerBodyConstraintRegions)
    }

    private func prioritizeLowerBodyPair(blocks: inout [RoutineBlock], mappings: inout [KGWorkoutPresetMapping]) {
        let desiredPresetIDs = ["bodyweight_squat", "bodyweight_lunge"]
            .filter { !blockedPresetIDs.contains($0) }
        var leadingBlocks: [RoutineBlock] = []
        var leadingMappings: [KGWorkoutPresetMapping] = []

        for presetID in desiredPresetIDs {
            if let mappingIndex = mappings.firstIndex(where: { $0.presetID == presetID }),
               let blockIndex = blocks.firstIndex(where: { block in
                   guard case let .preset(id) = block.exerciseRef else { return false }
                   return id == presetID
               }) {
                leadingMappings.append(mappings.remove(at: mappingIndex))
                leadingBlocks.append(blocks.remove(at: blockIndex))
            } else if let mapping = guideReadyPriorityMapping(for: presetID) {
                leadingMappings.append(mapping)
                leadingBlocks.append(defaultBlock(for: presetID))
            }
        }

        blocks = leadingBlocks + blocks
        mappings = leadingMappings + mappings
    }

    private func defaultBlock(for presetID: String) -> RoutineBlock {
        switch presetID {
        case "bodyweight_lunge":
            return RoutineBlock(exerciseRef: .preset(id: presetID), sets: 3, reps: 8, restSeconds: 75)
        case "bodyweight_squat":
            return RoutineBlock(exerciseRef: .preset(id: presetID), sets: 3, reps: 10, restSeconds: 75)
        default:
            return RoutineBlock(exerciseRef: .preset(id: presetID), sets: 1, reps: 8, restSeconds: 60)
        }
    }

    private func guideReadyPriorityMapping(for presetID: String) -> KGWorkoutPresetMapping? {
        let exerciseID: String
        switch presetID {
        case "bodyweight_squat":
            exerciseID = "Exercise:bodyweight_squat"
        case "bodyweight_lunge":
            exerciseID = "Exercise:bodyweight_lunge"
        default:
            return nil
        }
        let coverage = AssignmentExerciseTrackingCoverage.coverage(forExerciseID: exerciseID, in: graph)
        guard coverage.status == .guideReady else { return nil }
        return KGWorkoutPresetMapping(
            kgExerciseID: exerciseID,
            kgExerciseName: Self.appPresetName(for: presetID),
            presetID: presetID,
            readinessStatus: "guide_ready",
            reason: "Prioritized from the lower-body prompt because no active lower-body safety memory blocks this app preset."
        )
    }

    private static func appPresetName(for presetID: String) -> String {
        switch presetID {
        case "machine_chest_supported_row": return "Machine - Chest-Supported Row"
        case "single_arm_chest_supported_incline_row": return "Single-Arm Chest-Supported Incline Row"
        case "wide_grip_preacher_curl_with_ez_bar": return "Wide-Grip Preacher Curl with EZ Bar"
        case "suspension_tricep_press": return "Suspension Tricep Press"
        case "single_arm_cable_tricep_extension": return "Single-Arm Cable Tricep Extension"
        case "bench_lying_single_arm_dumbbell_tricep_extension": return "Bench-Lying Single-Arm Dumbbell Tricep Extension"
        case "single_arm_dumbbell_preacher_curl": return "Single-Arm Dumbbell Preacher Curl"
        case "bodyweight_pike": return "Bodyweight Pike"
        case "bodyweight_jumping_jack": return "Bodyweight Jumping Jack"
        case "resistance_band_reverse_curl": return "Resistance Band Reverse Curl"
        case "standing_miniband_hip_flexion": return "Standing Miniband Hip Flexion"
        case "bodyweight_lunge": return "Bodyweight Lunge"
        case "bodyweight_squat": return "Bodyweight Squat"
        case "bodyweight_pushup": return "Bodyweight Push-Up"
        case "bodyweight_plank": return "Bodyweight Plank"
        default:
            return presetID
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    private static func routineID(prompt: String) -> String {
        let slug = prompt
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "kg-\(slug.isEmpty ? "workout" : String(slug.prefix(48)))"
    }
}

private extension KGWorkoutMemoryReference {
    init(constraint: OverlayConstraint) {
        self.init(
            operationID: constraint.operationID,
            title: Self.title(for: constraint.value),
            sourceText: constraint.sourceText
        )
    }

    static func title(for value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

private extension KGWorkoutDecisionEvidence {
    init(summary: ExerciseSummary) {
        self.init(
            exerciseID: summary.exerciseID,
            name: summary.name,
            decision: summary.decision,
            reasonCodes: summary.reasonCodes,
            primaryReasonCode: summary.primaryReasonCode,
            primarySeverity: summary.primarySeverity,
            graphPaths: summary.graphPaths
        )
    }
}

private extension KGWorkoutAlternativeEvidence {
    init(summary: AlternativeSummary) {
        self.init(
            filteredExerciseID: summary.filteredExerciseID,
            alternativeExerciseID: summary.alternativeExerciseID,
            score: summary.score,
            graphPaths: summary.graphPaths
        )
    }
}
