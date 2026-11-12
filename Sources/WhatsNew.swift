import Foundation
import Combine

struct NewsText: Codable, Equatable {
  let fr: String
  let en: String
  func localized(_ language: String) -> String { language == "en" ? en : fr }
}

struct NewsEntry: Codable, Identifiable, Equatable {
  /// Permanent ID: editing a sentence or shipping a maintenance build must not
  /// notify users a second time. Only a new announcement gets a new ID.
  let id: String
  let date: String
  let version: String
  let icon: String
  let title: NewsText
  let body: NewsText
  let notify: Bool

  var publishedAt: Date {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(secondsFromGMT: 0)
    parser.dateFormat = "yyyy-MM-dd"
    return parser.date(from: date) ?? .distantPast
  }
  var formattedDate: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "dd.MM.yyyy"
    return formatter.string(from: publishedAt)
  }
}

final class WhatsNewStore: ObservableObject {
  static let shared = WhatsNewStore()
  static let readKey = "whatsNewReadAnnouncementIDs.v1"
  let entries: [NewsEntry]
  @Published private(set) var readIDs: Set<String>
  private let defaults: UserDefaults
  var unreadCount: Int { entries.filter { $0.notify && !readIDs.contains($0.id) }.count }

  init(defaults: UserDefaults = .standard, entries: [NewsEntry]? = nil, bundle: Bundle = .main) {
    self.defaults = defaults
    self.readIDs = Set(defaults.stringArray(forKey: Self.readKey) ?? [])
    let catalogue = entries ?? Self.load(bundle: bundle)
    var seen = Set<String>()
    // Same-day entries retain the editorial order of the catalogue.
    self.entries = catalogue.enumerated().filter { seen.insert($0.element.id).inserted }
      .sorted { a, b in a.element.date == b.element.date ? a.offset < b.offset : a.element.date > b.element.date }
      .map(\.element)
  }
  static func load(bundle: Bundle) -> [NewsEntry] {
    guard let url = bundle.url(forResource: "News", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let entries = try? JSONDecoder().decode([NewsEntry].self, from: data) else { return [] }
    return entries
  }
  func markAllRead() {
    let next = readIDs.union(entries.map(\.id))
    guard next != readIDs else { return }
    readIDs = next
    defaults.set(next.sorted(), forKey: Self.readKey)
  }
}
