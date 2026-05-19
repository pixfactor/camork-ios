import Testing
@testable import Camork

@Suite("Theme tokens")
struct ThemeTests {
    @Test("Spacing은 8pt 그리드를 따른다 (4의 배수)")
    func spacingFollows8ptGrid() {
        #expect(Spacing.xs == 4)
        #expect(Spacing.sm == 8)
        #expect(Spacing.md == 16)
        #expect(Spacing.lg == 24)
        #expect(Spacing.xl == 32)
        for value in [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl] {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0)
        }
    }

    @Test("CornerRadius 4단계 — 오름차순")
    func cornerRadiusStandards() {
        #expect(CornerRadius.sm == 6)
        #expect(CornerRadius.md == 12)
        #expect(CornerRadius.lg == 16)
        #expect(CornerRadius.xl == 24)
        let values = [CornerRadius.sm, CornerRadius.md, CornerRadius.lg, CornerRadius.xl]
        #expect(values == values.sorted())
    }
}
