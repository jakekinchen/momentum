import Foundation

struct ExpressionParser {
    private let tokens: [ExpressionToken]
    private var index = 0

    init(_ source: String) throws {
        var lexer = ExpressionLexer(source)
        tokens = try lexer.tokenize()
    }

    mutating func parse() throws -> ExpressionNode {
        let expression = try parseExpression()
        try consumeEOF()
        return expression
    }

    mutating func parsePredicate() throws -> PredicateExpression {
        let left = try parseExpression()
        let comparison = try parseComparison()
        let right = try parseExpression()
        try consumeEOF()
        return PredicateExpression(left: left, comparison: comparison, right: right)
    }

    private mutating func parseExpression() throws -> ExpressionNode {
        try parseAddition()
    }

    private mutating func parseAddition() throws -> ExpressionNode {
        var expression = try parseMultiplication()

        while true {
            if match(.plus) {
                expression = try .binary(.add, expression, parseMultiplication())
            } else if match(.minus) {
                expression = try .binary(.subtract, expression, parseMultiplication())
            } else {
                return expression
            }
        }
    }

    private mutating func parseMultiplication() throws -> ExpressionNode {
        var expression = try parseUnary()

        while true {
            if match(.star) {
                expression = try .binary(.multiply, expression, parseUnary())
            } else if match(.slash) {
                expression = try .binary(.divide, expression, parseUnary())
            } else {
                return expression
            }
        }
    }

    private mutating func parseUnary() throws -> ExpressionNode {
        if match(.minus) {
            return try .unaryMinus(parseUnary())
        }

        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> ExpressionNode {
        let token = advance()

        switch token {
        case let .number(value):
            return .number(value)
        case let .identifier(name):
            if match(.leftParen) {
                return try parseFunctionCall(name: name)
            }

            return name.contains(".") ? .landmark(name) : .signal(name)
        case .leftParen:
            let expression = try parseExpression()
            try consume(.rightParen, expected: ")")
            return expression
        default:
            throw ExpressionParseError.unexpectedToken(token.description)
        }
    }

    private mutating func parseComparison() throws -> ComparisonOperator {
        let token = advance()

        switch token {
        case .less:
            return .lessThan
        case .lessEqual:
            return .lessThanOrEqual
        case .greater:
            return .greaterThan
        case .greaterEqual:
            return .greaterThanOrEqual
        case .equalEqual:
            return .equal
        case .bangEqual:
            return .notEqual
        default:
            throw ExpressionParseError.expected("comparison operator", found: token.description)
        }
    }

    private mutating func parseFunctionCall(name: String) throws -> ExpressionNode {
        var arguments: [ExpressionNode] = []

        if match(.rightParen) {
            return .function(name: name, arguments: arguments)
        }

        repeat {
            arguments.append(try parseExpression())
        } while match(.comma)

        try consume(.rightParen, expected: ")")
        return .function(name: name, arguments: arguments)
    }

    private mutating func consume(_ expectedToken: ExpressionToken, expected: String) throws {
        let token = advance()
        guard token.sameCase(as: expectedToken) else {
            throw ExpressionParseError.expected(expected, found: token.description)
        }
    }

    private mutating func consumeEOF() throws {
        let token = advance()
        guard token == .eof else {
            throw ExpressionParseError.expected("end of expression", found: token.description)
        }
    }

    private func peek() -> ExpressionToken {
        tokens[index]
    }

    private mutating func advance() -> ExpressionToken {
        let token = tokens[index]
        index += 1
        return token
    }

    private mutating func match(_ expectedToken: ExpressionToken) -> Bool {
        guard peek().sameCase(as: expectedToken) else {
            return false
        }

        _ = advance()
        return true
    }
}

private extension ExpressionToken {
    func sameCase(as other: ExpressionToken) -> Bool {
        switch (self, other) {
        case (.number, .number),
             (.identifier, .identifier),
             (.plus, .plus),
             (.minus, .minus),
             (.star, .star),
             (.slash, .slash),
             (.less, .less),
             (.lessEqual, .lessEqual),
             (.greater, .greater),
             (.greaterEqual, .greaterEqual),
             (.equalEqual, .equalEqual),
             (.bangEqual, .bangEqual),
             (.leftParen, .leftParen),
             (.rightParen, .rightParen),
             (.comma, .comma),
             (.eof, .eof):
            return true
        default:
            return false
        }
    }
}
