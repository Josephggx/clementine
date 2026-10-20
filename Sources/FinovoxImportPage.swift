import Foundation

enum FinovoxImportPage {
  enum Route { case documents, signIn, other }
  static func route(for url: URL?) -> Route {
    guard let url, url.scheme == "https", url.host == "app.finovox.com" else { return .other }
    let path = url.path.lowercased()
    if path == "" || path == "/" { return .documents }
    if path.split(separator:"/").contains(where: { ["login", "signin", "sign-in", "auth"].contains(String($0)) }) {
      return .signIn
    }
    return .other
  }
}
