import Foundation

extension JiraExportProvider {
    func hardLimit(
        _ blocks: [JiraBlock],
        maxCharacters: Int
    ) -> [JiraBlock] {
        var characterBudget = 0
        var limitedBlocks: [JiraBlock] = []

        for block in blocks {
            let blockText = block.plainText
            let blockLength = blockText.count
            if characterBudget + blockLength <= maxCharacters {
                limitedBlocks.append(block)
                characterBudget += blockLength
                continue
            }

            let remainingCharacters = max(0, maxCharacters - characterBudget)
            guard remainingCharacters > 0 else {
                break
            }

            limitedBlocks.append(
                .paragraph(
                    text: TrackerExportPayloadBudget.truncated(
                        blockText,
                        maxCharacters: remainingCharacters
                    )
                )
            )
            break
        }

        return limitedBlocks
    }
}

struct JiraDocument: Encodable {
    let type = "doc"
    let version = 1
    let content: [JiraBlock]
}

struct JiraBlock: Encodable {
    let type: String
    let content: [JiraInline]?

    static func paragraph(text: String) -> JiraBlock {
        JiraBlock(type: "paragraph", content: [.text(text)])
    }

    static func bulletList(items: [String]) -> JiraBlock {
        JiraBlock(
            type: "bulletList",
            content: items.map { item in
                JiraInline.listItem(
                    JiraBlock(type: "paragraph", content: [.text(item)])
                )
            }
        )
    }

    var plainText: String {
        content?.map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ") ?? ""
    }
}

struct JiraInline: Encodable {
    let type: String
    let text: String?
    let content: [JiraBlock]?

    static func text(_ value: String) -> JiraInline {
        JiraInline(type: "text", text: value, content: nil)
    }

    static func listItem(_ block: JiraBlock) -> JiraInline {
        JiraInline(type: "listItem", text: nil, content: [block])
    }

    var plainText: String {
        let childText = content?.map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ") ?? ""
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if childText.isEmpty {
                return text
            }

            return "\(text) \(childText)"
        }

        return childText
    }
}

struct JiraADFNode: Decodable {
    let type: String?
    let text: String?
    let content: [JiraADFNode]?

    var plainText: String {
        let childText = content?.map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ") ?? ""
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if childText.isEmpty {
                return text
            }

            return [text, childText].joined(separator: " ")
        }

        return childText
    }
}
