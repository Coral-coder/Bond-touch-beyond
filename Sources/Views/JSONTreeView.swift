import SwiftUI

/// A collapsible, colour-coded tree of a parsed JSON value (as produced by
/// `JSONSerialization`). Objects and arrays expand/collapse; keys are tinted; strings,
/// numbers, booleans and null are colour-coded. Recursion is broken with `AnyView` so the
/// view type stays finite for arbitrarily nested data.
struct JSONNode: View {
    let key: String?
    let value: Any

    var body: some View {
        if let dict = value as? [String: Any] {
            branch(summary: "{\(dict.count)}") {
                ForEach(dict.keys.sorted(), id: \.self) { k in
                    AnyView(JSONNode(key: k, value: dict[k] ?? NSNull()))
                }
            }
        } else if let arr = value as? [Any] {
            branch(summary: "[\(arr.count)]") {
                ForEach(Array(arr.enumerated()), id: \.offset) { index, element in
                    AnyView(JSONNode(key: "\(index)", value: element))
                }
            }
        } else {
            leaf
        }
    }

    @ViewBuilder private func branch<C: View>(summary: String, @ViewBuilder content: @escaping () -> C) -> some View {
        DisclosureGroup {
            content()
        } label: {
            HStack(spacing: 6) {
                if let key { Text(key).foregroundStyle(Theme.accent).bold() }
                Text(summary).foregroundStyle(Theme.subtitle)
            }
            .font(.system(size: 12.5, design: .monospaced))
        }
        .tint(Theme.accent)
    }

    private var leaf: some View {
        HStack(alignment: .top, spacing: 6) {
            if let key { Text(key + ":").foregroundStyle(Theme.accent).bold() }
            Text(leafText).foregroundStyle(leafColor).textSelection(.enabled)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var leafText: String {
        if value is NSNull { return "null" }
        if let n = value as? NSNumber {
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if let s = value as? String { return "\"\(s)\"" }
        return "\(value)"
    }

    private var leafColor: Color {
        if value is NSNull { return Theme.subtitle }
        if let n = value as? NSNumber {
            return CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() ? Theme.pink : Theme.lime
        }
        return .white
    }
}
