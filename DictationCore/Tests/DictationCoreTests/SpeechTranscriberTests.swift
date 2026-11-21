import Foundation
import Testing
@testable import DictationCore

@MainActor @Suite struct SpeechTranscriberTests {
    private let supported = Set(
        ["en-US", "en-GB", "fr-FR", "fr-CA", "pt-BR", "pt-PT", "yue-CN", "zh-CN", "zh-TW"]
            .map(Locale.init(identifier:))
    )

    private func languages(preferred: [String]) -> [String] {
        SpeechTranscriber.languages(preferred: preferred, supported: supported).map(\.identifier)
    }

    @Test func listsSupportedLanguagesInOrderOfPreference() {
        #expect(languages(preferred: ["fr-FR", "tlh-US", "en-US"]) == ["fr-FR", "en-US"])
    }

    @Test func listsEachLanguageOnce() {
        #expect(languages(preferred: ["en-GB", "fr-FR", "en-US"]) == ["en-GB", "fr-FR"])
    }

    @Test func keepsARegionThatHasARecogniser() {
        #expect(languages(preferred: ["pt-PT", "fr-CA"]) == ["pt-PT", "fr-CA"])
    }

    @Test func replacesARegionThatHasNoRecogniser() {
        #expect(languages(preferred: ["fr-US", "en-AT", "pt"]) == ["fr-FR", "en-US", "pt-BR"])
    }

    @Test func picksTheChineseRegionByScript() {
        #expect(languages(preferred: ["zh-Hant-US"]) == ["zh-TW"])
        #expect(languages(preferred: ["zh-Hans-US"]) == ["zh-CN"])
    }

    @Test func settlesForAnyRegionThatHasARecogniser() {
        #expect(languages(preferred: ["yue-Hant-HK"]) == ["yue-CN"])
    }

    @Test func listsNothingWhenNoPreferredLanguageIsSupported() {
        #expect(languages(preferred: ["tlh-US"]).isEmpty)
    }

    @Test func keepsTheSavedLanguageWhileItIsOffered() {
        let offered = [Locale(identifier: "en-US"), Locale(identifier: "fr-FR")]
        #expect(SpeechTranscriber.language(saved: "fr-FR", among: offered) == offered[1])
    }

    @Test func fallsBackToTheMostPreferredLanguage() {
        let offered = [Locale(identifier: "en-US"), Locale(identifier: "fr-FR")]
        #expect(SpeechTranscriber.language(saved: "de-DE", among: offered) == offered[0])
        #expect(SpeechTranscriber.language(saved: nil, among: offered) == offered[0])
        #expect(SpeechTranscriber.language(saved: "fr-FR", among: []) == nil)
    }
}
