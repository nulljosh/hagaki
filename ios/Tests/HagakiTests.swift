import Testing
import Foundation
@testable import Hagaki

private func msg(_ from: String, junk: Bool = true, unsub: String? = "<https://x.example/u>") -> Message {
    Message(id: UUID().uuidString, from: from, subject: "s", snippet: nil, score: junk ? 3 : 0, reasons: [], isJunk: junk, category: junk ? "Junk" : nil, listUnsubscribe: unsub, oneClick: nil)
}

@Test func domainAndSenderName() {
    #expect(senderDomain("DealDrop <hello@DealDrop.example>") == "dealdrop.example")
    #expect(msg("\"PayPal\" <a@b.example>").sender == "PayPal")
    #expect(msg("plain@x.example").sender == "plain@x.example")
}

@Test func repeatSendersNeedTwoJunkMailsWithUnsubscribe() {
    let inbox = [msg("A <a@deal.example>"), msg("A <b@deal.example>"), msg("B <c@one.example>"),
                 msg("C <d@legit.example>", junk: false), msg("C <e@legit.example>", junk: false),
                 msg("D <f@nolink.example>", unsub: nil), msg("D <g@nolink.example>", unsub: nil)]
    let groups = repeatSenders(inbox)
    #expect(groups.map(\.domain) == ["deal.example"])
    #expect(groups[0].messages.count == 2)
}

@Test func requestsCarryTheBearerToken() {
    let r = API(token: "tok").request("api/messages")
    #expect(r.url?.host == "hagaki.heyitsmejosh.com")
    #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
}

@Test func messageDecodesWorkerJSON() throws {
    let json = #"[{"id":"d1","from":"Apple <a@x.example>","subject":"Act now","snippet":"s","score":3,"reasons":["urgency language"],"isJunk":true,"listUnsubscribe":"","oneClick":false}]"#
    let list = try JSONDecoder().decode([Message].self, from: Data(json.utf8))
    #expect(list.first?.isJunk == true)
}

@Test func keychainRoundTrip() {
    Keychain.set("test-key", "abc")
    #expect(Keychain.get("test-key") == "abc")
    Keychain.set("test-key", nil)
    #expect(Keychain.get("test-key") == nil)
}

@Test func smartFolderIsNilForPeople() throws {
    let json = #"[{"id":"1","from":"Stripe <r@stripe.com>","subject":"Receipt","snippet":"s","score":0,"reasons":[],"isJunk":false,"category":"Receipts","listUnsubscribe":"","oneClick":false},{"id":"2","from":"Sam <sam@x.org>","subject":"Lunch","snippet":"s","score":0,"reasons":[],"isJunk":false,"category":"Inbox","listUnsubscribe":"","oneClick":false}]"#
    let list = try JSONDecoder().decode([Message].self, from: Data(json.utf8))
    #expect(list[0].folder == "Receipts")
    #expect(list[1].folder == nil)
    #expect(smartFolders.count == 7)
}

@Test func organizeResultCountsEveryBox() throws {
    let r = try JSONDecoder().decode(OrganizeResult.self, from: Data(#"{"organized":{"Dev":2,"Travel":1},"failed":0}"#.utf8))
    #expect(r.total == 3)
}
