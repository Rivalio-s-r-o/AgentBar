import Testing
import Foundation
@testable import StatusBarKit

// --- Claude refresh response parse ---
@Test func claudeRefreshParseÚplný() {
    let d = Data(#"{"access_token":"newA","expires_in":3600,"refresh_token":"newR"}"#.utf8)
    let r = ClaudeRefreshParse.parse(d)
    #expect(r?.accessToken == "newA")
    #expect(r?.expiresInSeconds == 3600)
    #expect(r?.refreshToken == "newR")
}
@Test func claudeRefreshParseBezRefresh() {
    let r = ClaudeRefreshParse.parse(Data(#"{"access_token":"a","expires_in":60}"#.utf8))
    #expect(r?.refreshToken == nil)
    #expect(r?.accessToken == "a")
}
@Test func claudeRefreshParseNevalidníNil() {
    #expect(ClaudeRefreshParse.parse(Data("nonsense".utf8)) == nil)
    #expect(ClaudeRefreshParse.parse(Data(#"{"expires_in":60}"#.utf8)) == nil)  // chybí access_token
}

// --- Claude Keychain blob mutace ---
private let claudeBlob = Data(#"""
{"mcpOAuth":{"srv":"x"},"claudeAiOauth":{"accessToken":"oldA","refreshToken":"oldR","expiresAt":111,"subscriptionType":"max","scopes":["openid"],"clientId":"cid"}}
"""#.utf8)

@Test func claudeBlobMutaceZachováOstatní() throws {
    let out = ClaudeCredentialUpdate.updatedBlob(original: claudeBlob, accessToken: "newA", expiresAtMillis: 999, refreshToken: "newR")
    let json = try JSONSerialization.jsonObject(with: #require(out)) as! [String: Any]
    let oauth = json["claudeAiOauth"] as! [String: Any]
    #expect(oauth["accessToken"] as? String == "newA")
    #expect((oauth["expiresAt"] as? Double) == 999)
    #expect(oauth["refreshToken"] as? String == "newR")
    #expect(oauth["subscriptionType"] as? String == "max")          // zachováno
    #expect(oauth["clientId"] as? String == "cid")                  // zachováno
    #expect((json["mcpOAuth"] as? [String: Any])?["srv"] as? String == "x")  // zachováno
}
@Test func claudeBlobMutaceRefreshNilPonecháStarý() throws {
    let out = ClaudeCredentialUpdate.updatedBlob(original: claudeBlob, accessToken: "newA", expiresAtMillis: 5, refreshToken: nil)
    let oauth = (try JSONSerialization.jsonObject(with: #require(out)) as! [String: Any])["claudeAiOauth"] as! [String: Any]
    #expect(oauth["refreshToken"] as? String == "oldR")             // ponecháno
    #expect(oauth["accessToken"] as? String == "newA")
}
@Test func claudeBlobMutaceCizíStrukturaNil() {
    #expect(ClaudeCredentialUpdate.updatedBlob(original: Data(#"{"foo":1}"#.utf8), accessToken: "x", expiresAtMillis: 1, refreshToken: nil) == nil)
}

// --- Codex refresh response parse ---
@Test func codexRefreshParseÚplný() {
    let r = CodexRefreshParse.parse(Data(#"{"access_token":"a","token_type":"Bearer","expires_in":3600,"refresh_token":"r"}"#.utf8))
    #expect(r?.accessToken == "a")
    #expect(r?.refreshToken == "r")
}
@Test func codexRefreshParseNevalidníNil() {
    #expect(CodexRefreshParse.parse(Data(#"{"token_type":"Bearer"}"#.utf8)) == nil)
}

// --- Codex auth.json mutace ---
private let codexAuth = Data(#"""
{"auth_mode":"chatgpt","tokens":{"access_token":"oldA","refresh_token":"oldR","account_id":"acc","id_token":"idt"},"last_refresh":"2026-01-01T00:00:00Z"}
"""#.utf8)

@Test func codexAuthMutaceZachováOstatní() throws {
    let out = CodexAuthUpdate.updatedAuthJSON(original: codexAuth, accessToken: "newA", refreshToken: nil)
    let json = try JSONSerialization.jsonObject(with: #require(out)) as! [String: Any]
    let tokens = json["tokens"] as! [String: Any]
    #expect(tokens["access_token"] as? String == "newA")
    #expect(tokens["refresh_token"] as? String == "oldR")           // nil → ponecháno
    #expect(tokens["account_id"] as? String == "acc")               // zachováno
    #expect(tokens["id_token"] as? String == "idt")                 // zachováno
    #expect(json["auth_mode"] as? String == "chatgpt")              // zachováno
    #expect(json["last_refresh"] as? String == "2026-01-01T00:00:00Z")  // ZÁMĚRNĚ nezměněno
}
@Test func codexAuthMutaceRefreshRotace() throws {
    let out = CodexAuthUpdate.updatedAuthJSON(original: codexAuth, accessToken: "newA", refreshToken: "newR")
    let tokens = (try JSONSerialization.jsonObject(with: #require(out)) as! [String: Any])["tokens"] as! [String: Any]
    #expect(tokens["refresh_token"] as? String == "newR")
}
@Test func codexAuthMutaceCizíStrukturaNil() {
    #expect(CodexAuthUpdate.updatedAuthJSON(original: Data(#"{"foo":1}"#.utf8), accessToken: "x", refreshToken: nil) == nil)
}
