import Foundation
import CryptoKit

/// Reproduces Python json.dumps(sort_keys=True, separators=(",",":"), ensure_ascii=True)
/// for the fixed fingerprint payload, then sha256(...)[:16]. This guarantees the Swift
/// DecisionReceipt.constraint_fingerprint matches FitGraph's stable_fingerprint byte-for-byte.
public enum CanonicalJSON {
    /// JSON string escaping identical to Python's ensure_ascii encoder:
    /// escape " \ and the named control chars; other controls and all non-ASCII -> \uXXXX
    /// (astral chars become surrogate pairs); '/' is NOT escaped.
    public static func encodeString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{09}": out += "\\t"
            case "\u{0A}": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\u{0D}": out += "\\r"
            default:
                let v = scalar.value
                if v < 0x20 {
                    out += String(format: "\\u%04x", v)
                } else if v < 0x80 {
                    out.unicodeScalars.append(scalar)
                } else if v > 0xFFFF {
                    let u = v - 0x10000
                    out += String(format: "\\u%04x\\u%04x", 0xD800 + (u >> 10), 0xDC00 + (u & 0x3FF))
                } else {
                    out += String(format: "\\u%04x", v)
                }
            }
        }
        return out + "\""
    }

    /// Build the canonical fingerprint payload string. Top-level keys
    /// (available_equipment, constraints, exercise_id) and per-constraint keys
    /// (constraint_type, hard, negated, source_text, value) are already in
    /// sort_keys order. Equipment ids are sorted ascending (ASCII => code-point order).
    public static func fingerprintPayload(availableEquipment: [String],
                                          constraints: [ResolvedConstraint],
                                          exerciseID: String) -> String {
        let eq = availableEquipment.sorted().map(encodeString).joined(separator: ",")
        let cons = constraints.map { c -> String in
            "{"
            + "\"constraint_type\":" + encodeString(c.constraintType) + ","
            + "\"hard\":" + (c.hard ? "true" : "false") + ","
            + "\"negated\":" + (c.negated ? "true" : "false") + ","
            + "\"source_text\":" + encodeString(c.sourceText) + ","
            + "\"value\":" + encodeString(c.value)
            + "}"
        }.joined(separator: ",")
        return "{"
            + "\"available_equipment\":[" + eq + "],"
            + "\"constraints\":[" + cons + "],"
            + "\"exercise_id\":" + encodeString(exerciseID)
            + "}"
    }

    public static func sha256Prefix16(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    public static func fingerprint(availableEquipment: [String],
                                   constraints: [ResolvedConstraint],
                                   exerciseID: String) -> String {
        sha256Prefix16(fingerprintPayload(availableEquipment: availableEquipment,
                                          constraints: constraints, exerciseID: exerciseID))
    }
}
