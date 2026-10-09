import XCTest
@testable import LpxCore

final class ProjectSortingTests: XCTestCase {
    /// In natural name order, with dates: b is oldest, d newest, a and c share a date, e has none.
    private let names = ["a", "b", "c", "d", "e"]
    private let dates: [String: Int64] = ["a": 200, "b": 100, "c": 200, "d": 300, "e": 0]
    private func date(_ p: String) -> Int64? { dates[p] }

    func testNameAscendingKeepsTheNaturalOrder() {
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .name, ascending: true), date: date), names)
    }

    func testNameDescendingReversesIt() {
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .name, ascending: false), date: date), ["e", "d", "c", "b", "a"])
    }

    func testNewestFirst() {
        // equal dates (a, c) keep name order; e has no date and goes last
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .dateSaved, ascending: false), date: date), ["d", "a", "c", "b", "e"])
    }

    func testOldestFirst() {
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .dateSaved, ascending: true), date: date), ["b", "a", "c", "d", "e"])
    }

    func testProjectsWithoutADateAreLastInBothDirections() {
        let unknown: (String) -> Int64? = { $0 == "b" ? nil : self.dates[$0] }
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .dateSaved, ascending: true), date: unknown).last, "e")
        XCTAssertEqual(Array(ProjectSorting.sorted(names, by: ProjectOrder(field: .dateSaved, ascending: false), date: unknown).suffix(2)), ["b", "e"])
    }

    func testAnyListOfThingsWithAPathCanBeSorted() {
        let results = names.map { ProjectResult(path: "/m/\($0).logicx") }
        let sorted = ProjectSorting.sorted(results, by: ProjectOrder(field: .dateSaved, ascending: false), path: { $0.path },
                                           date: { self.dates[URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent] })
        XCTAssertEqual(sorted.map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent }, ["d", "a", "c", "b", "e"])
    }

    func testEmptyAndSingleListsAreFine() {
        XCTAssertEqual(ProjectSorting.sorted([String](), by: ProjectOrder(field: .dateSaved), date: date), [])
        XCTAssertEqual(ProjectSorting.sorted(["a"], by: ProjectOrder(field: .dateSaved, ascending: false), date: date), ["a"])
    }

    func testEachFieldStartsInItsNaturalDirection() {
        XCTAssertEqual(ProjectOrder.initial(for: .name), ProjectOrder(field: .name, ascending: true))
        XCTAssertEqual(ProjectOrder.initial(for: .dateSaved), ProjectOrder(field: .dateSaved, ascending: false), "newest first")
    }
}
