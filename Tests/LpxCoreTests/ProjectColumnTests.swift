import XCTest
@testable import LpxCore

final class ProjectColumnTests: XCTestCase {
    func testDatesAreShownByDefaultAndTheRestIsOptional() {
        XCTAssertEqual(ProjectColumn.defaultVisible, [.dateModified, .dateCreated])
        XCTAssertEqual(Set(ProjectColumn.allCases), [.dateModified, .dateCreated, .dateSaved, .size, .tags])
    }

    func testTheChoiceSurvivesSavingAndLoading() {
        let chosen: Set<ProjectColumn> = [.size, .tags, .dateModified]
        XCTAssertEqual(ProjectColumn.decode(ProjectColumn.encode(chosen)), chosen)
        XCTAssertEqual(ProjectColumn.decode(ProjectColumn.encode([])), [], "hiding every optional column is allowed")
    }

    func testNothingSavedMeansTheDefaultsAndUnknownNamesAreIgnored() {
        XCTAssertEqual(ProjectColumn.decode(nil), ProjectColumn.defaultVisible)
        XCTAssertEqual(ProjectColumn.decode(["Size", "Colour of the moon"]), [.size])
    }

    func testClickingAColumnHeaderSortsByItAndTagsDoNotSort() {
        XCTAssertEqual(ProjectColumn.dateModified.sortField, .dateModified)
        XCTAssertEqual(ProjectColumn.size.sortField, .size)
        XCTAssertNil(ProjectColumn.tags.sortField)
        for column in ProjectColumn.allCases where column != .tags { XCTAssertNotNil(column.sortField) }
    }
}
