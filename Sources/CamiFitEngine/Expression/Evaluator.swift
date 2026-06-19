import Foundation

struct ExpressionEvaluator {
    let frame: PoseFrame
    let signals: [String: SignalValue]
    let minConfidence: Double

    func evaluate(_ expression: ExpressionNode) -> SignalValue {
        switch evaluateValue(expression) {
        case let .number(value, confidence):
            guard value.isFinite else {
                return .invalid(reason: "non-finite numeric result")
            }
            return .valid(value, confidence: confidence)
        case .landmark:
            return .invalid(reason: "landmark cannot be the final expression value")
        case let .invalid(reason):
            return .invalid(reason: reason)
        }
    }

    private func evaluateValue(_ expression: ExpressionNode) -> EvaluatedValue {
        switch expression {
        case let .number(value):
            return .number(value, confidence: 1)
        case let .signal(name):
            return evaluateSignal(name)
        case let .landmark(reference):
            return evaluateLandmark(reference)
        case let .unaryMinus(expression):
            return evaluateNumeric(expression) { value, confidence in
                .number(-value, confidence: confidence)
            }
        case let .binary(operation, left, right):
            return evaluateBinary(operation, left: left, right: right)
        case let .function(name, arguments):
            return evaluateFunction(name, arguments: arguments)
        }
    }

    private func evaluateSignal(_ name: String) -> EvaluatedValue {
        guard let value = signals[name] else {
            return .invalid("missing signal \(name)")
        }

        switch value {
        case let .valid(number, confidence):
            return .number(number, confidence: confidence)
        case let .invalid(reason):
            return .invalid("signal \(name) invalid: \(reason)")
        }
    }

    private func evaluateLandmark(_ reference: String) -> EvaluatedValue {
        guard let landmark = frame.landmark(named: reference) else {
            return .invalid("missing landmark \(reference)")
        }

        guard landmark.confidence >= minConfidence else {
            return .invalid(
                "low confidence landmark \(reference) visibility=\(landmark.visibility) presence=\(landmark.presence) threshold=\(minConfidence)"
            )
        }

        return .landmark(landmark, reference: reference, confidence: landmark.confidence)
    }

    private func evaluateBinary(_ operation: BinaryOperator, left: ExpressionNode, right: ExpressionNode) -> EvaluatedValue {
        let leftValue = evaluateValue(left)
        let rightValue = evaluateValue(right)

        guard case let .number(leftNumber, leftConfidence) = leftValue else {
            return leftValue.invalidOrTypeError("left operand must be numeric")
        }

        guard case let .number(rightNumber, rightConfidence) = rightValue else {
            return rightValue.invalidOrTypeError("right operand must be numeric")
        }

        let confidence = min(leftConfidence, rightConfidence)

        switch operation {
        case .add:
            return finiteNumber(leftNumber + rightNumber, confidence: confidence)
        case .subtract:
            return finiteNumber(leftNumber - rightNumber, confidence: confidence)
        case .multiply:
            return finiteNumber(leftNumber * rightNumber, confidence: confidence)
        case .divide:
            guard abs(rightNumber) > Geometry.epsilon else {
                return .invalid("divide by zero")
            }
            return finiteNumber(leftNumber / rightNumber, confidence: confidence)
        }
    }

    private func evaluateFunction(_ name: String, arguments: [ExpressionNode]) -> EvaluatedValue {
        switch name {
        case "abs":
            guard arguments.count == 1 else {
                return .invalid("abs expects 1 argument")
            }
            return evaluateNumeric(arguments[0]) { value, confidence in
                .number(abs(value), confidence: confidence)
            }
        case "angle":
            guard arguments.count == 3 else {
                return .invalid("angle expects 3 arguments")
            }
            return evaluateAngle(arguments)
        case "angle_to_vertical":
            guard arguments.count == 2 else {
                return .invalid("angle_to_vertical expects 2 arguments")
            }
            return evaluateAngleToVertical(arguments)
        case "angle_to_horizontal":
            guard arguments.count == 2 else {
                return .invalid("angle_to_horizontal expects 2 arguments")
            }
            return evaluateAngleToHorizontal(arguments)
        case "distance":
            guard arguments.count == 2 else {
                return .invalid("distance expects 2 arguments")
            }
            return evaluateDistance(arguments)
        case "max":
            guard !arguments.isEmpty else {
                return .invalid("max expects at least 1 argument")
            }
            return evaluateExtremum(arguments, select: Swift.max)
        case "midpoint":
            guard arguments.count == 2 else {
                return .invalid("midpoint expects 2 arguments")
            }
            return evaluateMidpoint(arguments)
        case "min":
            guard !arguments.isEmpty else {
                return .invalid("min expects at least 1 argument")
            }
            return evaluateExtremum(arguments, select: Swift.min)
        case "ratio":
            guard arguments.count == 2 else {
                return .invalid("ratio expects 2 arguments")
            }
            return evaluateRatio(arguments)
        case "signed_angle":
            guard arguments.count == 3 else {
                return .invalid("signed_angle expects 3 arguments")
            }
            return evaluateSignedAngle(arguments)
        default:
            return .invalid("unsupported function \(name)")
        }
    }

    private func evaluateAngle(_ arguments: [ExpressionNode]) -> EvaluatedValue {
        let first = evaluateValue(arguments[0])
        let vertex = evaluateValue(arguments[1])
        let third = evaluateValue(arguments[2])

        guard case let .landmark(a, _, confidenceA) = first else {
            return first.invalidOrTypeError("angle argument 1 must be a landmark")
        }
        guard case let .landmark(b, _, confidenceB) = vertex else {
            return vertex.invalidOrTypeError("angle argument 2 must be a landmark")
        }
        guard case let .landmark(c, _, confidenceC) = third else {
            return third.invalidOrTypeError("angle argument 3 must be a landmark")
        }

        let ab = Vector(dx: a.x - b.x, dy: a.y - b.y)
        let cb = Vector(dx: c.x - b.x, dy: c.y - b.y)

        guard let degrees = Geometry.angleBetween(ab, cb) else {
            return .invalid("degenerate angle")
        }

        return .number(degrees, confidence: min(confidenceA, confidenceB, confidenceC))
    }

    private func evaluateAngleToVertical(_ arguments: [ExpressionNode]) -> EvaluatedValue {
        let first = evaluateValue(arguments[0])
        let second = evaluateValue(arguments[1])

        guard case let .landmark(a, _, confidenceA) = first else {
            return first.invalidOrTypeError("angle_to_vertical argument 1 must be a landmark")
        }
        guard case let .landmark(b, _, confidenceB) = second else {
            return second.invalidOrTypeError("angle_to_vertical argument 2 must be a landmark")
        }

        let vector = Vector(dx: a.x - b.x, dy: a.y - b.y)
        guard let degrees = Geometry.angleBetween(vector, Vector(dx: 0, dy: -1)) else {
            return .invalid("degenerate angle_to_vertical")
        }

        return .number(degrees, confidence: min(confidenceA, confidenceB))
    }

    private func evaluateAngleToHorizontal(_ arguments: [ExpressionNode]) -> EvaluatedValue {
        let first = evaluateValue(arguments[0])
        let second = evaluateValue(arguments[1])

        guard case let .landmark(a, _, confidenceA) = first else {
            return first.invalidOrTypeError("angle_to_horizontal argument 1 must be a landmark")
        }
        guard case let .landmark(b, _, confidenceB) = second else {
            return second.invalidOrTypeError("angle_to_horizontal argument 2 must be a landmark")
        }

        let vector = Vector(dx: a.x - b.x, dy: a.y - b.y)
        guard let degrees = Geometry.angleBetween(vector, Vector(dx: 1, dy: 0)) else {
            return .invalid("degenerate angle_to_horizontal")
        }

        return .number(degrees, confidence: min(confidenceA, confidenceB))
    }

    private func evaluateDistance(_ arguments: [ExpressionNode]) -> EvaluatedValue {
        let first = evaluateValue(arguments[0])
        let second = evaluateValue(arguments[1])

        guard case let .landmark(a, _, confidenceA) = first else {
            return first.invalidOrTypeError("distance argument 1 must be a landmark")
        }
        guard case let .landmark(b, _, confidenceB) = second else {
            return second.invalidOrTypeError("distance argument 2 must be a landmark")
        }

        let dx = a.x - b.x
        let dy = a.y - b.y
        return finiteNumber(sqrt((dx * dx) + (dy * dy)), confidence: min(confidenceA, confidenceB))
    }

    private func evaluateExtremum(
        _ arguments: [ExpressionNode],
        select: (Double, Double) -> Double
    ) -> EvaluatedValue {
        var selectedValue: Double?
        var selectedConfidence = 1.0

        for argument in arguments {
            let value = evaluateValue(argument)
            guard case let .number(number, confidence) = value else {
                return value.invalidOrTypeError("argument must be numeric")
            }

            selectedValue = selectedValue.map { select($0, number) } ?? number
            selectedConfidence = min(selectedConfidence, confidence)
        }

        guard let selectedValue else {
            return .invalid("argument must be numeric")
        }

        return finiteNumber(selectedValue, confidence: selectedConfidence)
    }

    private func evaluateMidpoint(_ arguments: [ExpressionNode]) -> EvaluatedValue {
        let first = evaluateValue(arguments[0])
        let second = evaluateValue(arguments[1])

        guard case let .landmark(a, _, confidenceA) = first else {
            return first.invalidOrTypeError("midpoint argument 1 must be a landmark")
        }
        guard case let .landmark(b, _, confidenceB) = second else {
            return second.invalidOrTypeError("midpoint argument 2 must be a landmark")
        }

        return .landmark(
            PoseLandmark(
                x: (a.x + b.x) / 2,
                y: (a.y + b.y) / 2,
                z: (a.z + b.z) / 2,
                visibility: min(a.visibility, b.visibility),
                presence: min(a.presence, b.presence)
            ),
            reference: "midpoint",
            confidence: min(confidenceA, confidenceB)
        )
    }

    private func evaluateRatio(_ arguments: [ExpressionNode]) -> EvaluatedValue {
        let numerator = evaluateValue(arguments[0])
        let denominator = evaluateValue(arguments[1])

        guard case let .number(numeratorValue, numeratorConfidence) = numerator else {
            return numerator.invalidOrTypeError("ratio numerator must be numeric")
        }
        guard case let .number(denominatorValue, denominatorConfidence) = denominator else {
            return denominator.invalidOrTypeError("ratio denominator must be numeric")
        }
        guard abs(denominatorValue) > Geometry.epsilon else {
            return .invalid("ratio denominator is zero")
        }

        return finiteNumber(numeratorValue / denominatorValue, confidence: min(numeratorConfidence, denominatorConfidence))
    }

    private func evaluateSignedAngle(_ arguments: [ExpressionNode]) -> EvaluatedValue {
        let first = evaluateValue(arguments[0])
        let vertex = evaluateValue(arguments[1])
        let third = evaluateValue(arguments[2])

        guard case let .landmark(a, _, confidenceA) = first else {
            return first.invalidOrTypeError("signed_angle argument 1 must be a landmark")
        }
        guard case let .landmark(b, _, confidenceB) = vertex else {
            return vertex.invalidOrTypeError("signed_angle argument 2 must be a landmark")
        }
        guard case let .landmark(c, _, confidenceC) = third else {
            return third.invalidOrTypeError("signed_angle argument 3 must be a landmark")
        }

        let ab = Vector(dx: a.x - b.x, dy: a.y - b.y)
        let cb = Vector(dx: c.x - b.x, dy: c.y - b.y)
        guard let degrees = Geometry.signedAngleBetween(ab, cb) else {
            return .invalid("degenerate signed_angle")
        }

        return .number(degrees, confidence: min(confidenceA, confidenceB, confidenceC))
    }

    private func evaluateNumeric(_ expression: ExpressionNode, transform: (Double, Double) -> EvaluatedValue) -> EvaluatedValue {
        let value = evaluateValue(expression)

        guard case let .number(number, confidence) = value else {
            return value.invalidOrTypeError("argument must be numeric")
        }

        return transform(number, confidence)
    }

    private func finiteNumber(_ value: Double, confidence: Double) -> EvaluatedValue {
        value.isFinite ? .number(value, confidence: confidence) : .invalid("non-finite numeric result")
    }
}

private enum EvaluatedValue {
    case number(Double, confidence: Double)
    case landmark(PoseLandmark, reference: String, confidence: Double)
    case invalid(String)

    func invalidOrTypeError(_ typeError: String) -> EvaluatedValue {
        switch self {
        case let .invalid(reason):
            return .invalid(reason)
        case .number, .landmark:
            return .invalid(typeError)
        }
    }
}

private struct Vector {
    let dx: Double
    let dy: Double

    var magnitude: Double {
        sqrt(dx * dx + dy * dy)
    }
}

private enum Geometry {
    static let epsilon = 1e-12

    static func angleBetween(_ first: Vector, _ second: Vector) -> Double? {
        let firstMagnitude = first.magnitude
        let secondMagnitude = second.magnitude

        guard firstMagnitude > epsilon, secondMagnitude > epsilon else {
            return nil
        }

        let dot = first.dx * second.dx + first.dy * second.dy
        let cosine = max(-1, min(1, dot / (firstMagnitude * secondMagnitude)))
        return acos(cosine) * 180 / Double.pi
    }

    static func signedAngleBetween(_ first: Vector, _ second: Vector) -> Double? {
        let firstMagnitude = first.magnitude
        let secondMagnitude = second.magnitude

        guard firstMagnitude > epsilon, secondMagnitude > epsilon else {
            return nil
        }

        let dot = first.dx * second.dx + first.dy * second.dy
        let determinant = first.dx * second.dy - first.dy * second.dx
        return atan2(determinant, dot) * 180 / Double.pi
    }
}
