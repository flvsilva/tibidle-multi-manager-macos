import AppKit
import TibidleCore
import WebKit

// Sample data only: no game connection and no real profile is touched.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dashboard-preview.png"
let light = CommandLine.arguments.contains("light")
let width = CommandLine.arguments.contains("phone") ? 390.0 : 1280.0

var clock = Date().addingTimeInterval(-6 * 3600)
let store = DashboardStore(databaseURL: nil, now: { clock })
store.setAccountNames(["Main EK", "Druid farm", "Paladin", "Conta 4"])

let parties = [
    #"[{"name":"Sir Bruno","vocation":"knight","level":187,"hp":2100,"maxHp":2650,"mana":700,"maxMana":900},{"name":"Lia Heals","vocation":"druid","level":180,"hp":1000,"maxHp":1100,"mana":4100,"maxMana":5200}]"#,
    #"[{"name":"Mossy","vocation":"druid","level":122,"hp":700,"maxHp":800,"mana":2000,"maxMana":3300}]"#,
    #"[{"name":"Arrowtip","vocation":"paladin","level":143,"hp":1200,"maxHp":1500,"mana":1300,"maxMana":2100}]"#,
]
for account in 0..<3 {
    store.ingest(account: account, json: #"{"type":"welcome","data":{"account":{"name":"acc\#(account)","level":100}}}"#)
    store.ingest(account: account, json: #"{"type":"hunt_started","data":{"huntId":\#(account + 1),"state":{"party":\#(parties[account])}}}"#)
}
var hunt = [1, 2, 3]
for minute in 0..<360 {
    clock = clock.addingTimeInterval(60)
    for account in 0..<3 where !(account == 2 && (150..<200).contains(minute)) {
        let t = Double(minute)
        let elapsed = Double((minute % 120) + 1) * 60000
        let xph = Int([2_400_000.0, 900_000, 1_500_000][account] * (1 + 0.15 * sin(t / 23 + Double(account))))
        let loot = Int(elapsed / 3_600_000 * [480_000.0, 210_000, 300_000][account] * (1 + 0.2 * cos(t / 31)))
        let supplies = Int(elapsed / 3_600_000 * [390_000.0, 60_000, 330_000][account])
        if minute % 120 == 0 && minute > 0 {
            store.ingest(account: account, json: #"{"type":"ended","data":{"summary":{"huntId":\#(hunt[account]),"reason":"\#(["stop", "cap_full", "death"][account])","elapsedSec":7200,"level":{"start":\#(140 + account),"end":\#(141 + account)},"xp":"\#(xph * 2)","xpPerHour":\#(xph),"lootGold":\#(loot),"suppliesGold":\#(supplies),"balance":\#(loot - supplies),"killsTotal":1800,"deaths":\#(account == 2 ? 1 : 0)}}}"#)
            hunt[account] += 10
            store.ingest(account: account, json: #"{"type":"hunt_started","data":{"huntId":\#(hunt[account]),"state":{"party":\#(parties[account])}}}"#)
        }
        store.ingest(account: account, json: #"{"type":"frame","data":{"state":{"party":\#(parties[account])},"analyzer":{"elapsedMs":\#(Int(elapsed)),"xp":"\#(Int(Double(xph) * elapsed / 3_600_000))","xpPerHour":\#(xph),"killsTotal":\#(minute % 120 * 14),"kills":{"Dragon":\#(minute % 120 * 9),"Dragon Lord":\#(minute % 120 * 2),"Dragon Hatchling":\#(minute % 120 * 3)},"lootGold":\#(loot),"suppliesGold":\#(supplies),"damageDealt":\#(Int(elapsed / 20)),"damageTaken":\#(Int(elapsed / 90)),"healingDone":\#(Int(elapsed / 110))}}}"#)
    }
}
store.ingest(account: 2, json: #"{"type":"ended","data":{"summary":{"huntId":99,"reason":"death","elapsedSec":3100,"level":{"start":143,"end":143},"xp":"900000","xpPerHour":1045000,"lootGold":120000,"suppliesGold":170000,"balance":-50000,"killsTotal":700,"deaths":1}}}"#)
store.ingest(account: 3, json: #"{"type":"_closed","data":{}}"#)
clock = Date()

let server = DashboardServer(store: store)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 1700))
if light { webView.appearance = NSAppearance(named: .aqua) } else { webView.appearance = NSAppearance(named: .darkAqua) }
let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = webView
window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
window.orderFrontRegardless()

server.onReady = { port in
    webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!))
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        webView.evaluateJavaScript("document.querySelector('main').scrollHeight") { height, _ in
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: width, height: min((height as? Double ?? 1600) + 40, 1700))
            webView.takeSnapshot(with: config) { image, error in
                if let image, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: output))
                    print("saved \(output)")
                } else {
                    print("snapshot failed: \(error?.localizedDescription ?? "?")")
                }
                exit(0)
            }
        }
    }
}
server.start(port: 18787)
app.run()
