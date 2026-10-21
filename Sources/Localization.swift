import Foundation
import Combine

/// The French source strings are the fallback, including their existing spelling
/// and punctuation. Only presentation text goes through this layer; format IDs,
/// paths, document content and automation scripts keep their original values.
final class AppLanguage: ObservableObject {
  static let shared = AppLanguage()
  static let changed = Notification.Name("ClementineLanguageChanged")
  static let defaultsKey = "interfaceLanguage"
  @Published var code: String {
    didSet {
      guard oldValue != code else { return }
      defaults.set(code,forKey:Self.defaultsKey)
      defaults.set([code],forKey:"AppleLanguages")
      NotificationCenter.default.post(name:Self.changed,object:nil)
    }
  }
  var locale: Locale { Locale(identifier:code) }
  private let defaults: UserDefaults
  private let english: [String:String]
  private let uppercaseEnglish: [String:String]
  private lazy var patterns: [(NSRegularExpression,String)] = {
    english.keys.filter { $0.contains("{0}") }.sorted { $0.count > $1.count }.compactMap { key in
      var pattern = NSRegularExpression.escapedPattern(for:key)
      for index in 0..<20 {
        pattern = pattern.replacingOccurrences(of:NSRegularExpression.escapedPattern(for:"{\(index)}"),with:"(.*?)")
      }
      guard let regex = try? NSRegularExpression(pattern:"^"+pattern+"$",options:.dotMatchesLineSeparators) else { return nil }
      return (regex,english[key]!)
    }
  }()

  init(defaults:UserDefaults = .standard, translations:[String:String]? = nil) {
    self.defaults = defaults
    let stored = defaults.string(forKey:Self.defaultsKey) ?? "fr"
    code = ["fr","en"].contains(stored) ? stored : "fr"
    if let translations { english = translations }
    else if let url = Bundle.main.url(forResource:"en",withExtension:"json",subdirectory:"Localization"),
      let data = try? Data(contentsOf:url),
      let values = try? JSONDecoder().decode([String:String].self,from:data) { english = values }
    else { english = [:] }
    uppercaseEnglish = english.reduce(into:[:]) { result, pair in result[pair.key.uppercased()] = pair.value.uppercased() }
  }

  func translate(_ source:String) -> String {
    guard code == "en" else { return source }
    if let value = english[source] { return value }
    // Category headings may display the existing source label in uppercase.
    if source == source.uppercased(), let value = uppercaseEnglish[source] {
      return value
    }
    // Some native APIs supply an already formatted status or error. Keep its
    // captured values intact rather than translating filenames or user data.
    let range = NSRange(source.startIndex...,in:source)
    for (regex,template) in patterns {
      if let match = regex.firstMatch(in:source,range:range) {
        let values = (1..<match.numberOfRanges).map { index in
          Range(match.range(at:index),in:source).map { String(source[$0]) } ?? ""
        }
        return Self.render(template,values:values)
      }
    }
    return source
  }

  func resolve(_ message:AppMessage) -> String {
    guard code == "en", let template = english[message.key] else { return message.original }
    return Self.render(template,values:message.values)
  }

  private static func render(_ template:String,values:[String]) -> String {
    guard let regex = try? NSRegularExpression(pattern:#"\{([0-9]+)\}"#) else { return template }
    var result = template
    for match in regex.matches(in:template,range:NSRange(template.startIndex...,in:template)).reversed() {
      guard let number = Range(match.range(at:1),in:template), let index = Int(template[number]),
        values.indices.contains(index), let range = Range(match.range,in:result) else { continue }
      result.replaceSubrange(range,with:values[index])
    }
    return result
  }
}

struct AppMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  let key: String
  let original: String
  let values: [String]
  init(stringLiteral value:String) { key=value; original=value; values=[] }
  init(stringInterpolation: StringInterpolation) {
    key=stringInterpolation.key; original=stringInterpolation.original; values=stringInterpolation.values
  }
  struct StringInterpolation: StringInterpolationProtocol {
    var key = "", original = "", values: [String] = []
    init(literalCapacity:Int,interpolationCount:Int) { values.reserveCapacity(interpolationCount) }
    mutating func appendLiteral(_ value:String) { key += value; original += value }
    mutating func appendInterpolation<T>(_ value:T) {
      let rendered = String(describing:value)
      key += "{\(values.count)}"; original += rendered; values.append(rendered)
    }
  }
}

func tr(_ message:AppMessage) -> String { AppLanguage.shared.resolve(message) }
func trString(_ source:String) -> String { AppLanguage.shared.translate(source) }
