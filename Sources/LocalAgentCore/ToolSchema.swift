import MCP
import Foundation

// A deliberately explicit subset. Unsupported constraints block a tool instead of being ignored.
public enum ToolSchema {
    private static let supported: Set<String> = ["type", "properties", "required", "additionalProperties", "items", "enum",
        "description", "title", "default", "examples", "$schema", "minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems"]
    public static func checkSupported(_ schema: Value, depth: Int = 0) throws {
        guard depth < 20, case .object(let object) = schema,
              Set(object.keys).isSubset(of: supported) else {
            throw AgentError.rejected("Tool uses an unsupported JSON Schema constraint.")
        }
        if let type = object["type"] {
            guard let name = type.stringValue, ["object", "array", "string", "integer", "number", "boolean", "null"].contains(name) else {
                throw AgentError.rejected("Tool schema uses an unsupported type.")
            }
        }
        if let properties = object["properties"] {
            guard case .object(let fields) = properties else { throw AgentError.rejected("Invalid tool properties.") }
            for child in fields.values { try checkSupported(child, depth: depth + 1) }
        }
        if let additional = object["additionalProperties"], additional.boolValue == nil {
            try checkSupported(additional, depth: depth + 1)
        }
        if let items = object["items"] { try checkSupported(items, depth: depth + 1) }
        if let required = object["required"] {
            guard case .array(let names) = required, names.allSatisfy({ $0.stringValue != nil }) else {
                throw AgentError.rejected("Invalid required tool fields.")
            }
        }
        if let values = object["enum"], values.arrayValue == nil { throw AgentError.rejected("Invalid tool enum.") }
        for key in ["minLength", "maxLength", "minItems", "maxItems"] {
            if let value = object[key], value.intValue == nil || value.intValue! < 0 {
                throw AgentError.rejected("Invalid tool size constraint.")
            }
        }
        for key in ["minimum", "maximum"] {
            if let value = object[key], number(value) == nil { throw AgentError.rejected("Invalid numeric tool constraint.") }
        }
    }
    public static func validate(_ value: Value, schema: Value) throws {
        try checkSupported(schema)
        guard case .object(let object) = schema else { return }
        if let values = object["enum"]?.arrayValue, !values.contains(value) { throw invalid() }
        if let type = object["type"]?.stringValue {
            let matches: Bool
            switch (type, value) {
            case ("object", .object), ("array", .array), ("string", .string), ("integer", .int),
                 ("number", .int), ("number", .double), ("boolean", .bool), ("null", .null): matches = true
            default: matches = false
            }
            guard matches else { throw invalid() }
        }
        if case .object(let fields) = value {
            let properties = object["properties"]?.objectValue ?? [:]
            for key in object["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
                guard fields[key] != nil else { throw invalid() }
            }
            for (key, child) in fields {
                if let childSchema = properties[key] { try validate(child, schema: childSchema) }
                else if let additional = object["additionalProperties"] {
                    if additional.boolValue == false { throw invalid() }
                    if additional.boolValue == nil { try validate(child, schema: additional) }
                }
            }
        }
        if case .array(let items) = value {
            try bounds(items.count, min: object["minItems"]?.intValue, max: object["maxItems"]?.intValue)
            if let itemSchema = object["items"] { for item in items { try validate(item, schema: itemSchema) } }
        }
        if case .string(let text) = value {
            try bounds(text.unicodeScalars.count, min: object["minLength"]?.intValue, max: object["maxLength"]?.intValue)
        }
        if let numeric = number(value) {
            if let min = object["minimum"].flatMap(number), numeric < min { throw invalid() }
            if let max = object["maximum"].flatMap(number), numeric > max { throw invalid() }
        }
    }
    private static func number(_ value: Value) -> Double? {
        switch value { case .int(let n): Double(n); case .double(let n): n; default: nil }
    }
    private static func bounds(_ count: Int, min: Int?, max: Int?) throws {
        if let min, count < min { throw invalid() }; if let max, count > max { throw invalid() }
    }
    private static func invalid() -> AgentError { .rejected("Tool arguments failed schema validation.") }
}
