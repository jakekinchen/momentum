import Foundation

indirect enum ExpressionNode: Equatable {
    case number(Double)
    case signal(String)
    case landmark(String)
    case unaryMinus(ExpressionNode)
    case binary(BinaryOperator, ExpressionNode, ExpressionNode)
    case function(name: String, arguments: [ExpressionNode])

    var signalReferences: Set<String> {
        switch self {
        case .number, .landmark:
            return []
        case let .signal(name):
            return [name]
        case let .unaryMinus(expression):
            return expression.signalReferences
        case let .binary(_, left, right):
            return left.signalReferences.union(right.signalReferences)
        case let .function(_, arguments):
            return arguments.reduce(into: Set<String>()) { references, argument in
                references.formUnion(argument.signalReferences)
            }
        }
    }
}

enum BinaryOperator: Equatable {
    case add
    case subtract
    case multiply
    case divide
}
