import Foundation

public enum SignalEvaluatorError: Error, Equatable, CustomStringConvertible {
    case parseError(signal: String, reason: String)

    public var description: String {
        switch self {
        case let .parseError(signal, reason):
            return "parse_error(signal: \(signal), reason: \(reason))"
        }
    }
}

public struct SignalEvaluator {
    private let program: ExerciseProgram
    private let parsedSignals: [String: ExpressionNode]
    private let evaluationOrder: [String]

    public init(program: ExerciseProgram) throws {
        self.program = program

        var parsedSignals: [String: ExpressionNode] = [:]
        for name in program.signals.keys.sorted() {
            do {
                var parser = try ExpressionParser(program.signals[name] ?? "")
                parsedSignals[name] = try parser.parse()
            } catch {
                throw SignalEvaluatorError.parseError(signal: name, reason: String(describing: error))
            }
        }

        self.parsedSignals = parsedSignals
        evaluationOrder = Self.orderSignals(parsedSignals)
    }

    public func evaluateSignals(frame: PoseFrame) -> [String: SignalValue] {
        var values: [String: SignalValue] = [:]

        for name in evaluationOrder {
            guard let expression = parsedSignals[name] else {
                continue
            }

            let evaluator = ExpressionEvaluator(
                frame: frame,
                signals: values,
                minConfidence: program.validity.minSignalConfidence
            )
            values[name] = evaluator.evaluate(expression)
        }

        return values
    }

    public func evaluateExpression(
        _ expression: String,
        frame: PoseFrame,
        signals: [String: SignalValue] = [:]
    ) -> SignalValue {
        do {
            var parser = try ExpressionParser(expression)
            let node = try parser.parse()
            let evaluator = ExpressionEvaluator(
                frame: frame,
                signals: signals,
                minConfidence: program.validity.minSignalConfidence
            )
            return evaluator.evaluate(node)
        } catch {
            return .invalid(reason: "parse error: \(error)")
        }
    }

    private static func orderSignals(_ parsedSignals: [String: ExpressionNode]) -> [String] {
        let signalNames = Set(parsedSignals.keys)
        var ordered: [String] = []
        var visited = Set<String>()

        func visit(_ name: String) {
            guard !visited.contains(name) else {
                return
            }

            visited.insert(name)
            let dependencies = parsedSignals[name]?.signalReferences.intersection(signalNames) ?? []
            for dependency in dependencies.sorted() {
                visit(dependency)
            }
            ordered.append(name)
        }

        for name in signalNames.sorted() {
            visit(name)
        }

        return ordered
    }
}
