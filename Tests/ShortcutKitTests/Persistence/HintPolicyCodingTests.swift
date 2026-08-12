import Foundation
@testable import ShortcutKit
import Testing

@Suite("HintPolicyCoding") struct HintPolicyCodingTests {
    @Test func persistedStringRoundTrips() {
        #expect(HintPolicy.always.persistedString == "always")
        #expect(HintPolicy.oncePerSession.persistedString == "once-per-session")
        #expect(HintPolicy.timeout(30).persistedString == "timeout:30.0")

        #expect(HintPolicy(persistedString: "always") == .always)
        #expect(HintPolicy(persistedString: "once-per-session") == .oncePerSession)
        #expect(HintPolicy(persistedString: "timeout:30.0") == .timeout(30))
        #expect(HintPolicy(persistedString: "timeout:0.1") == .timeout(0.1))
    }

    @Test func invalidPersistedStringsReturnNil() {
        #expect(HintPolicy(persistedString: "timeout") == nil)
        #expect(HintPolicy(persistedString: "timeout:") == nil)
        #expect(HintPolicy(persistedString: "timeout:abc") == nil)
        #expect(HintPolicy(persistedString: "timeout:1:2") == nil)
        #expect(HintPolicy(persistedString: "nonsense") == nil)
        #expect(HintPolicy(persistedString: "") == nil)
    }

    @Test func jsonPreferencesRoundTrip() throws {
        let prefs = Preferences(hintsEnabled: false, hintFrequency: .timeout(30))
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(Preferences.self, from: data) == prefs)
    }

    // Invalid policy text must not discard the rest of the persisted state.
    @Test func jsonMalformedHintFrequencyDecodesToNilInsteadOfThrowing() throws {
        let json = Data(#"{"hintsEnabled":true,"hintFrequency":"bogus"}"#.utf8)
        let prefs = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(prefs.hintsEnabled == true)
        #expect(prefs.hintFrequency == nil)
    }
}
