import Foundation
import Testing
@testable import NetPulse

struct ProductSiteTests {
    @Test(arguments: [
        ("status.sentry.io", "https://sentry.io"),
        ("www.vercel-status.com", "https://vercel.com"),
        ("githubstatus.com", "https://github.com"),
        ("example.com", "https://example.com"),
    ])
    func mapsStatusHostToProductSite(host: String, site: String) {
        #expect(StatusProbe.productSite(forStatusHost: host)?.absoluteString == site)
    }
}

struct HealthTests {
    @Test(arguments: [
        ("none", Health.ok),
        ("minor", .degraded),
        ("major", .down),
        ("critical", .down),
        ("other", .unknown),
    ])
    func statuspage(indicator: String, expected: Health) {
        let json = #"{"page": {"name": "Sentry"}, "status": {"indicator": "\#(indicator)"}}"#
        #expect(StatusProbe.statuspageHealth(from: Data(json.utf8)) == expected)
    }

    @Test(arguments: [
        (100, Health.ok),
        (200, .degraded),
        (300, .degraded),
        (400, .degraded),
        (500, .down),
        (600, .down),
        (999, .unknown),
    ])
    func statusio(code: Int, expected: Health) {
        let json = #"{"result": {"status_overall": {"status_code": \#(code)}}}"#
        #expect(StatusProbe.statusioHealth(from: Data(json.utf8)) == expected)
    }

    @Test(arguments: [
        ("UP", Health.ok),
        ("HASISSUES", .degraded),
        ("UNDERMAINTENANCE", .degraded),
        ("OTHER", .unknown),
    ])
    func instatus(status: String, expected: Health) {
        let json = #"{"page": {"name": "Acme", "status": "\#(status)"}}"#
        #expect(StatusProbe.instatusHealth(from: Data(json.utf8)) == expected)
    }

    @Test(arguments: [
        ("[]", Health.ok),
        (#"[{"type": "incident"}]"#, .degraded),
        (#"[{"type": "incident"}, {"type": "outage"}]"#, .down),
    ])
    func slack(incidents: String, expected: Health) {
        let json = #"{"active_incidents": \#(incidents)}"#
        #expect(StatusProbe.slackHealth(from: Data(json.utf8)) == expected)
    }

    @Test(arguments: [
        (#"[{"end": "2026-01-01T00:00:00Z", "severity": "high"}]"#, Health.ok),
        (#"[{"severity": "low"}]"#, .degraded),
        (#"[{"severity": "low"}, {"severity": "high"}]"#, .down),
    ])
    func googleCloud(json: String, expected: Health) {
        #expect(StatusProbe.googleCloudHealth(from: Data(json.utf8)) == expected)
    }

    @Test func unreadablePayloadIsUnknown() {
        #expect(StatusProbe.statuspageHealth(from: Data("not json".utf8)) == .unknown)
    }
}
