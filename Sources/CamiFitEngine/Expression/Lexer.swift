import Foundation

enum ExpressionToken: Equatable, CustomStringConvertible {
    case number(Double)
    case identifier(String)
    case plus
    case minus
    case star
    case slash
    case leftParen
    case rightParen
    case comma
    case eof

    var description: String {
        switch self {
        case let .number(value):
            return "\(value)"
        case let .identifier(value):
            return value
        case .plus:
            return "+"
        case .minus:
            return "-"
        case .star:
            return "*"
        case .slash:
            return "/"
        case .leftParen:
            return "("
        case .rightParen:
            return ")"
        case .comma:
            return ","
        case .eof:
            return "<eof>"
        }
    }
}

enum ExpressionParseError: Error, Equatable, CustomStringConvertible {
    case unexpectedCharacter(Character, offset: Int)
    case unexpectedToken(String)
    case expected(String, found: String)

    var description: String {
        switch self {
        case let .unexpectedCharacter(character, offset):
            return "unexpected character '\(character)' at offset \(offset)"
        case let .unexpectedToken(token):
            return "unexpected token \(token)"
        case let .expected(expected, found):
            return "expected \(expected), found \(found)"
        }
    }
}

struct ExpressionLexer {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) {
        characters = Array(source)
    }

    mutating func tokenize() throws -> [ExpressionToken] {
        var tokens: [ExpressionToken] = []

        while let character = peek() {
            if character.isWhitespace {
                advance()
                continue
            }

            if character.isNumber || character == "." {
                tokens.append(try lexNumber())
                continue
            }

            if character.isIdentifierStart {
                tokens.append(lexIdentifier())
                continue
            }

            switch character {
            case "+":
                advance()
                tokens.append(.plus)
            case "-":
                advance()
                tokens.append(.minus)
            case "*":
                advance()
                tokens.append(.star)
            case "/":
                advance()
                tokens.append(.slash)
            case "(":
                advance()
                tokens.append(.leftParen)
            case ")":
                advance()
                tokens.append(.rightParen)
            case ",":
                advance()
                tokens.append(.comma)
            default:
                throw ExpressionParseError.unexpectedCharacter(character, offset: index)
            }
        }

        tokens.append(.eof)
        return tokens
    }

    private mutating func lexNumber() throws -> ExpressionToken {
        let start = index
        var sawDecimal = false

        while let character = peek(), character.isNumber || character == "." {
            if character == "." {
                if sawDecimal {
                    break
                }
                sawDecimal = true
            }
            advance()
        }

        let raw = String(characters[start ..< index])
        guard let value = Double(raw) else {
            throw ExpressionParseError.unexpectedToken(raw)
        }

        return .number(value)
    }

    private mutating func lexIdentifier() -> ExpressionToken {
        let start = index

        while let character = peek(), character.isIdentifierPart {
            advance()
        }

        return .identifier(String(characters[start ..< index]))
    }

    private func peek() -> Character? {
        guard index < characters.count else {
            return nil
        }

        return characters[index]
    }

    private mutating func advance() {
        index += 1
    }
}

private extension Character {
    var isIdentifierStart: Bool {
        self == "_" || isLetter
    }

    var isIdentifierPart: Bool {
        isIdentifierStart || isNumber || self == "."
    }
}
