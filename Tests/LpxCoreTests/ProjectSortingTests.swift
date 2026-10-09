import XCTest
@testable import LpxCore

final class ProjectSortingTests: XCTestCase {
    /// In natural name order, with dates: b is oldest, d newest, a and c share a date, e has none.
    private let names = ["a", "b", "c", "d", "e"]
    private let dates: [String: Int64] = ["a": 200, "b": 100, "c": 200, "d": 300, "e": 0]
    private func date(_ p: String) -> Int64? { dates[p] }

    func testNameAscendingKeepsTheNaturalOrder() {
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .name, ascending: true), value: date), names)
    }

    func testNameDescendingReversesIt() {
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .name, ascending: false), value: date), ["e", "d", "c", "b", "a"])
    }

    func testNewestFirst() {
        // equal dates (a, c) keep name order; e has no date and goes last
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .dateSaved, ascending: false), value: date), ["d", "a", "c", "b", "e"])
    }

    func testOldestFirst() {
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .dateSaved, ascending: true), value: date), ["b", "a", "c", "d", "e"])
    }

    func testProjectsWithoutADateAreLastInBothDirections() {
        let unknown: (String) -> Int64? = { $0 == "b" ? nil : self.dates[$0] }
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .dateSaved, ascending: true), value: unknown).last, "e")
        XCTAssertEqual(Array(ProjectSorting.sorted(names, by: ProjectOrder(field: .dateSaved, ascending: false), value: unknown).suffix(2)), ["b", "e"])
    }

    func testAnyListOfThingsWithAPathCanBeSorted() {
        let results = names.map { ProjectResult(path: "/m/\($0).logicx") }
        let sorted = ProjectSorting.sorted(results, by: ProjectOrder(field: .dateSaved, ascending: false), path: { $0.path },
                                           value: { self.dates[URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent] })
        XCTAssertEqual(sorted.map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent }, ["d", "a", "c", "b", "e"])
    }

    func testEmptyAndSingleListsAreFine() {
        XCTAssertEqual(ProjectSorting.sorted([String](), by: ProjectOrder(field: .dateSaved), value: date), [])
        XCTAssertEqual(ProjectSorting.sorted(["a"], by: ProjectOrder(field: .dateSaved, ascending: false), value: date), ["a"])
    }

    func testEachFieldStartsInItsNaturalDirection() {
        XCTAssertEqual(ProjectOrder.initial(for: .name), ProjectOrder(field: .name, ascending: true))
        for field in [ProjectSortField.dateSaved, .dateModified, .dateCreated] {
            XCTAssertEqual(ProjectOrder.initial(for: field), ProjectOrder(field: field, ascending: false), "\(field): newest first")
        }
        XCTAssertEqual(ProjectOrder.initial(for: .size), ProjectOrder(field: .size, ascending: false), "largest first")
    }

    func testSizesSortLikeDates() {
        let sizes: [String: Int64] = ["a": 500, "b": 5_000_000, "c": 500, "d": 20, "e": 0]
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .size, ascending: false), value: { sizes[$0] }), ["b", "a", "c", "d", "e"])
        XCTAssertEqual(ProjectSorting.sorted(names, by: ProjectOrder(field: .size, ascending: true), value: { sizes[$0] }), ["d", "a", "c", "b", "e"])
    }

    func testEveryFieldIsADateOrNot() {
        XCTAssertEqual(ProjectSortField.allCases.filter(\.isDate), [.dateModified, .dateCreated, .dateSaved])
    }
}
