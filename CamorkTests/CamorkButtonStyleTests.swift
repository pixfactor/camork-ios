import Testing
@testable import Camork

@Suite("CamorkButton style resolution")
struct CamorkButtonStyleTests {
    @Test("primary는 borderedProminent + accent token")
    func primary() {
        let resolved = CamorkButton.resolveStyle(.primary)
        #expect(resolved.isProminent == true)
        #expect(resolved.tint == .accent)
    }

    @Test("secondary는 bordered + systemDefault (HIG: borderedProminent 1개 원칙)")
    func secondary() {
        let resolved = CamorkButton.resolveStyle(.secondary)
        #expect(resolved.isProminent == false)
        #expect(resolved.tint == .systemDefault)
    }

    @Test("destructive는 borderedProminent + destructive token")
    func destructive() {
        let resolved = CamorkButton.resolveStyle(.destructive)
        #expect(resolved.isProminent == true)
        #expect(resolved.tint == .destructive)
    }
}
