import Foundation

enum UpdateFeed {
  /// Only our moving GitHub "latest" URL needs a unique request. Immutable
  /// archives and signatures remain untouched; local test feeds stay local.
  static func isLatestRelease(_ url:URL)->Bool {
    url.scheme == "https" && url.host?.lowercased() == "github.com" &&
      ["/Josephggx/clementine/releases/latest/download/appcast.xml",
       "/Josephggx/clementine-releases/releases/latest/download/appcast.xml"].contains(url.path)
  }
  static func freshURL(_ configured:String,nonce:String=UUID().uuidString)->String? {
    guard let url=URL(string:configured),isLatestRelease(url),
      var components=URLComponents(url:url,resolvingAgainstBaseURL:false) else {return nil}
    var query=components.queryItems ?? []
    query.removeAll {$0.name == "clementine_check"}
    query.append(URLQueryItem(name:"clementine_check",value:nonce))
    components.queryItems=query
    return components.url?.absoluteString
  }
}
