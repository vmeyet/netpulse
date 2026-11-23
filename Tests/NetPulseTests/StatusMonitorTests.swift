import Testing
@testable import NetPulse

struct NormalizedLinkTests {
    @Test(arguments: [
        ("status.sentry.io", "https://status.sentry.io"),
        ("  https://status.claude.com\n", "https://status.claude.com"),
        ("http://example.com/status", "http://example.com/status"),
    ])
    func acceptsLinks(typed: String, expected: String) {
        #expect(StatusMonitor.normalized(typed)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "not a url"])
    func rejectsNonLinks(typed: String) {
        #expect(StatusMonitor.normalized(typed) == nil)
    }
}
