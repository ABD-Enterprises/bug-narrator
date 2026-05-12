#!/usr/bin/env swift

import ApplicationServices
import Foundation

guard CommandLine.arguments.count >= 2,
      let pid = pid_t(CommandLine.arguments[1]) else {
    fputs("usage: assistive_technology_ax_snapshot.swift <pid> [required text...]\n", stderr)
    exit(2)
}

let requiredText = Array(CommandLine.arguments.dropFirst(2))
let root = AXUIElementCreateApplication(pid)

func attribute(_ element: AXUIElement, _ name: String) -> String? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard result == .success, let value else { return nil }

    if CFGetTypeID(value) == CFStringGetTypeID() {
        return value as? String
    }

    if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
    }

    return String(describing: value)
}

func children(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let array = value as? [AXUIElement] else {
        return []
    }

    return array
}

var lines: [String] = []

func walk(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 8) {
    guard depth <= maxDepth else { return }

    let role = attribute(element, kAXRoleAttribute) ?? "?"
    let title = attribute(element, kAXTitleAttribute) ?? ""
    let description = attribute(element, kAXDescriptionAttribute) ?? ""
    let value = attribute(element, kAXValueAttribute) ?? ""
    let help = attribute(element, kAXHelpAttribute) ?? ""
    let enabled = attribute(element, kAXEnabledAttribute) ?? ""

    let shouldPrint = !title.isEmpty
        || !description.isEmpty
        || !value.isEmpty
        || !help.isEmpty
        || role.contains("Window")
        || role.contains("Button")
        || role.contains("Text")
        || role.contains("CheckBox")
        || role.contains("PopUp")
        || role.contains("Radio")

    if shouldPrint {
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)role=\(role) title=\(title) desc=\(description) value=\(value) help=\(help) enabled=\(enabled)")
    }

    for child in children(of: element) {
        walk(child, depth: depth + 1, maxDepth: maxDepth)
    }
}

var windowsRef: CFTypeRef?
let result = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windowsRef)

print("AX trusted: \(AXIsProcessTrusted())")
print("windows result: \(result.rawValue)")

if let windows = windowsRef as? [AXUIElement] {
    print("window_count: \(windows.count)")
    for window in windows {
        walk(window)
    }
}

let text = lines.joined(separator: "\n")
print(text)

var foundMissingText = false

for needle in requiredText {
    let didFind = text.localizedCaseInsensitiveContains(needle)
    print("CHECK \(needle): \(didFind ? "pass" : "miss")")
    foundMissingText = foundMissingText || !didFind
}

exit(foundMissingText ? 1 : 0)
