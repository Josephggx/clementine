import Foundation

let data=try Data(contentsOf:URL(fileURLWithPath:"Resources/News.json"))
let entries=try JSONDecoder().decode([NewsEntry].self,from:data)
let suite="clementine-news-test-"+UUID().uuidString
let defaults=UserDefaults(suiteName:suite)!
let betaDefaults=UserDefaults(suiteName:suite+"-beta")!
defer { defaults.removePersistentDomain(forName:suite); betaDefaults.removePersistentDomain(forName:suite+"-beta") }
var checks=0
func check(_ condition: @autoclosure ()->Bool,_ label:String) {checks += 1;precondition(condition(),label)}
check(entries.count==10,"Ten retrospective announcements")
check(Set(entries.map(\.id)).count==entries.count,"Permanent unique IDs")
for entry in entries {
  check(entry.publishedAt != .distantPast,"Date parses")
  check(!entry.title.fr.isEmpty && !entry.title.en.isEmpty && !entry.body.fr.isEmpty && !entry.body.en.isEmpty,"Both languages complete")
  check(entry.title.localized("fr")==entry.title.fr && entry.title.localized("en")==entry.title.en,"Language selection")
  check(entry.formattedDate == entry.date.split(separator:"-").reversed().joined(separator:"."),"Exact DD.MM.YYYY badge date")
}
let initial=WhatsNewStore(defaults:defaults,entries:entries)
check(initial.unreadCount==0,"First public release exposes history without a notification")
check(entries.allSatisfy { !$0.notify },"Retrospective entries remain quiet")
check(defaults.object(forKey:WhatsNewStore.readKey)==nil,"Loading the sidebar does not mark anything as read")
initial.markAllRead();check(initial.unreadCount==0,"Click clears count immediately")
initial.markAllRead();check(initial.unreadCount==0,"Repeated clicks are harmless")
check(WhatsNewStore(defaults:defaults,entries:entries).unreadCount==0,"Read state survives app restart and a build without new announcements")
check(WhatsNewStore(defaults:betaDefaults,entries:entries).unreadCount==0,"First-release history is quiet for fresh beta preferences too")
func newEntry(_ id:String,notify:Bool,date:String="2026-11-12") -> NewsEntry {
  NewsEntry(id:id,date:date,version:"next",icon:"bell",title:NewsText(fr:"Une nouveauté",en:"Something new"),body:NewsText(fr:"À découvrir.",en:"Take a look."),notify:notify)
}
let upgraded=WhatsNewStore(defaults:defaults,entries:entries+[newEntry("new",notify:true),newEntry("quiet",notify:false)])
check(upgraded.unreadCount==1,"Only important new announcements notify")
check(WhatsNewStore(defaults:betaDefaults,entries:upgraded.entries).unreadCount==1,"Future announcement notifies even if initial history was never opened")
check(upgraded.entries.first?.id=="new","Newest first, same-day editorial order stable")
upgraded.markAllRead();check(upgraded.unreadCount==0,"Reading new release clears its badge")
let rolledBack=WhatsNewStore(defaults:defaults,entries:entries);rolledBack.markAllRead()
check(WhatsNewStore(defaults:defaults,entries:upgraded.entries).unreadCount==0,"Downgrade then upgrade does not resurrect read entries")
let backfilled=WhatsNewStore(defaults:defaults,entries:entries+[newEntry("backfill",notify:true,date:"2026-10-01")])
check(backfilled.unreadCount==1 && backfilled.entries.last?.id=="backfill","Backdated announcement is still new if ID is new")
let edited=NewsEntry(id:entries[0].id,date:entries[0].date,version:"fixed",icon:"bell",title:NewsText(fr:"Texte corrigé",en:"Corrected text"),body:entries[0].body,notify:true)
check(WhatsNewStore(defaults:defaults,entries:[edited]).unreadCount==0,"Wording edits do not renotify")
check(WhatsNewStore(defaults:defaults,entries:[newEntry("unique",notify:true),newEntry("unique",notify:true)]).unreadCount==1,"Duplicate IDs cannot inflate the badge")
check(WhatsNewStore(defaults:defaults,entries:[]).unreadCount==0,"Empty catalogue has no badge")
let english=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:URL(fileURLWithPath:"Resources/Localization/en.json")))
for key in ["Nouveautés","Les nouveautés arrivent bientôt.","{0} nouveautés non lues"] {check(english[key] != nil,"Translated UI: \(key)")}
print("PASS \(checks) news checks: dates, FR/EN, read persistence, upgrades, quiet updates, rollbacks, independent beta")
