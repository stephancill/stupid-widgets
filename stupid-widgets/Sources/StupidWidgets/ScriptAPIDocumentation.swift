import Foundation

struct ScriptAPIDocumentation: Sendable {
  struct Spec: Decodable, Sendable {
    let source: Source
    let types: [String: TypeDocumentation]
    let globals: [String: MemberDocumentation]
    let functions: [String: MemberDocumentation]
  }

  struct Source: Decodable, Sendable {
    let name: String
    let version: String
  }

  struct TypeDocumentation: Decodable, Sendable {
    let name: String
    let summary: String?
    let description: String?
    let url: String?
    let constructors: [MemberDocumentation]
    let properties: [MemberDocumentation]
    let methods: [MemberDocumentation]
    let runtimeMembers: [String]?
  }

  struct MemberDocumentation: Decodable, Sendable {
    struct Parameter: Decodable, Sendable {
      let name: String?
      let type: String?
      let description: String?
    }

    let name: String?
    let signature: String?
    let summary: String?
    let description: String?
    let url: String?
    let parameters: [Parameter]?
    let returns: String?
  }

  static let bundledResult = Result { try bundled() }

  private let spec: Spec

  init(data: Data) throws {
    spec = try JSONDecoder().decode(Spec.self, from: data)
  }

  func lookup(query: String) -> String {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return json(["error": "query must be non-empty."])
    }

    if let type = type(named: query) {
      return typeResult(type)
    }

    let qualified = query.split(separator: ".", maxSplits: 1).map(String.init)
    if qualified.count == 2, let type = type(named: qualified[0]),
      let member = members(of: type).first(where: {
        $0.documentation.name?.caseInsensitiveCompare(qualified[1]) == .orderedSame
      })
    {
      return memberResult(owner: type.name, kind: member.kind, member: member.documentation)
    }

    if let global = namedMember(in: spec.globals, name: query) {
      return memberResult(owner: nil, kind: "global", member: global)
    }
    if let function = namedMember(in: spec.functions, name: query) {
      return memberResult(owner: nil, kind: "function", member: function)
    }

    let normalizedQuery = query.lowercased()
    let tokens = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let results = searchRecords().compactMap { record -> (Int, [String: Any])? in
      let name = record.name.lowercased()
      let qualifiedName = record.qualifiedName.lowercased()
      let searchable = [qualifiedName, record.signature, record.summary]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
      guard tokens.allSatisfy(searchable.contains) else { return nil }

      let score: Int
      if qualifiedName == normalizedQuery {
        score = 100
      } else if name == normalizedQuery {
        score = 90
      } else if qualifiedName.hasPrefix(normalizedQuery) {
        score = 80
      } else if name.hasPrefix(normalizedQuery) {
        score = 70
      } else {
        score = 50
      }
      return (
        score,
        compact([
          "kind": record.kind,
          "name": record.qualifiedName,
          "signature": record.signature,
          "summary": record.summary,
        ])
      )
    }
    .sorted {
      $0.0 == $1.0
        ? (($0.1["name"] as? String) ?? "") < (($1.1["name"] as? String) ?? "")
        : $0.0 > $1.0
    }

    return json([
      "canonical_source": "\(spec.source.name) \(spec.source.version)",
      "query": query,
      "results": results.prefix(12).map(\.1),
      "truncated": results.count > 12,
    ])
  }

  private static func bundled() throws -> ScriptAPIDocumentation {
    guard let url = Bundle.main.url(forResource: "scriptable-api", withExtension: "json") else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try ScriptAPIDocumentation(data: Data(contentsOf: url))
  }

  private func type(named name: String) -> TypeDocumentation? {
    spec.types.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  private func namedMember(
    in values: [String: MemberDocumentation], name: String
  ) -> MemberDocumentation? {
    values.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  private func members(
    of type: TypeDocumentation
  ) -> [(kind: String, documentation: MemberDocumentation)] {
    type.constructors.map { ("constructor", $0) }
      + type.properties.map { ("property", $0) }
      + type.methods.map { ("method", $0) }
  }

  private func typeResult(_ type: TypeDocumentation) -> String {
    json(
      compact([
        "canonical_source": "\(spec.source.name) \(spec.source.version)",
        "kind": "type",
        "name": type.name,
        "summary": type.summary,
        "description": shortened(type.description, limit: 1_200),
        "constructors": type.constructors.map(memberSummary),
        "properties": type.properties.map(memberSummary),
        "methods": type.methods.map(memberSummary),
        "runtime_members": type.runtimeMembers,
        "url": type.url,
      ]))
  }

  private func memberResult(
    owner: String?, kind: String, member: MemberDocumentation
  ) -> String {
    json(
      compact([
        "canonical_source": "\(spec.source.name) \(spec.source.version)",
        "kind": kind,
        "owner": owner,
        "name": member.name,
        "signature": member.signature,
        "summary": member.summary,
        "description": shortened(member.description, limit: 1_200),
        "parameters": member.parameters?.map {
          compact([
            "name": $0.name,
            "type": $0.type,
            "description": shortened($0.description, limit: 600),
          ])
        },
        "returns": shortened(member.returns, limit: 600),
        "url": member.url,
      ]))
  }

  private func memberSummary(_ member: MemberDocumentation) -> [String: Any] {
    compact([
      "name": member.name,
      "signature": member.signature,
      "summary": member.summary,
    ])
  }

  private struct SearchRecord {
    let kind: String
    let name: String
    let qualifiedName: String
    let signature: String?
    let summary: String?
  }

  private func searchRecords() -> [SearchRecord] {
    var records = spec.types.values.map {
      SearchRecord(
        kind: "type", name: $0.name, qualifiedName: $0.name, signature: nil,
        summary: $0.summary)
    }
    for type in spec.types.values {
      records += members(of: type).compactMap { member in
        guard let name = member.documentation.name else { return nil }
        return SearchRecord(
          kind: member.kind,
          name: name,
          qualifiedName: "\(type.name).\(name)",
          signature: member.documentation.signature,
          summary: member.documentation.summary
        )
      }
    }
    records += spec.globals.compactMap { name, member in
      SearchRecord(
        kind: "global", name: name, qualifiedName: name, signature: member.signature,
        summary: member.summary)
    }
    records += spec.functions.compactMap { name, member in
      SearchRecord(
        kind: "function", name: name, qualifiedName: name, signature: member.signature,
        summary: member.summary)
    }
    return records
  }

  private func shortened(_ value: String?, limit: Int) -> String? {
    guard let value else { return nil }
    guard value.count > limit else { return value }
    return String(value.prefix(limit)) + "..."
  }

  private func compact(_ values: [String: Any?]) -> [String: Any] {
    values.compactMapValues { $0 }
  }

  private func json(_ value: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let string = String(data: data, encoding: .utf8)
    else { return "{\"error\":\"Could not encode API documentation.\"}" }
    return string
  }
}
