import Foundation
let latest="https://github.com/Josephggx/clementine-releases/releases/latest/download/appcast.xml"
let first=UpdateFeed.freshURL(latest,nonce:"one")!
let second=UpdateFeed.freshURL(latest,nonce:"two")!
precondition(first != second)
precondition(URLComponents(string:first)!.queryItems == [URLQueryItem(name:"clementine_check",value:"one")])
let replaced=UpdateFeed.freshURL(latest+"?clementine_check=old&keep=yes",nonce:"new")!
precondition(URLComponents(string:replaced)!.queryItems == [URLQueryItem(name:"keep",value:"yes"),URLQueryItem(name:"clementine_check",value:"new")])
precondition(UpdateFeed.freshURL("http://localhost:8765/appcast.xml") == nil)
precondition(UpdateFeed.freshURL("https://github.com/Josephggx/clementine-releases/releases/download/v1.0.10/appcast.xml") == nil)
precondition(UpdateFeed.freshURL("https://example.com/appcast.xml") == nil)
let canonical="https://github.com/Josephggx/clementine/releases/latest/download/appcast.xml"
precondition(UpdateFeed.freshURL(canonical,nonce:"canonical") == canonical+"?clementine_check=canonical")
precondition(UpdateFeed.freshURL("https://github.com/other/clementine/releases/latest/download/appcast.xml") == nil)
precondition(UpdateFeed.freshURL("https://github.com/Josephggx/clementine/releases/download/v1.0.16/appcast.xml") == nil)
print("PASS: fresh latest URL per check, existing query preservation, immutable/local/other feeds unchanged")
