import XCTest
@testable import Downward

final class TaskListContinuationPlanTests: XCTestCase {
    func testReturnAtEndOfTaskCreatesNextTask() throws {
        let text = "- [ ] task" as NSString
        let plan = try XCTUnwrap(
            TaskListContinuationPlan.make(
                in: text,
                editedRange: NSRange(location: text.length, length: 0),
                replacementText: "\n"
            )
        )

        XCTAssertEqual(plan.replacementRange, NSRange(location: text.length, length: 0))
        XCTAssertEqual(plan.replacement, "\n- [ ] ")
        XCTAssertEqual(plan.selectionAfter, NSRange(location: text.length + 7, length: 0))
    }

    func testReturnAtEndOfNumberedTaskCreatesNextNumber() throws {
        let text = "9. [x] task" as NSString
        let plan = try XCTUnwrap(
            TaskListContinuationPlan.make(
                in: text,
                editedRange: NSRange(location: text.length, length: 0),
                replacementText: "\n"
            )
        )

        XCTAssertEqual(plan.replacement, "\n10. [ ] ")
    }

    func testReturnAgainOnGeneratedEmptyTaskRemovesTaskMarker() throws {
        let text = "- [ ] task\n- [ ] " as NSString
        let plan = try XCTUnwrap(
            TaskListContinuationPlan.make(
                in: text,
                editedRange: NSRange(location: text.length, length: 0),
                replacementText: "\n"
            )
        )

        let updated = text.replacingCharacters(in: plan.replacementRange, with: plan.replacement)

        XCTAssertEqual(updated, "- [ ] task\n")
        XCTAssertEqual(plan.selectionAfter, NSRange(location: (updated as NSString).length, length: 0))
    }

    func testReturnInMiddleOfTaskUsesDefaultEditing() {
        let text = "- [ ] task" as NSString

        XCTAssertNil(
            TaskListContinuationPlan.make(
                in: text,
                editedRange: NSRange(location: 4, length: 0),
                replacementText: "\n"
            )
        )
    }

    func testReturnWithSelectionUsesDefaultEditing() {
        let text = "- [ ] task" as NSString

        XCTAssertNil(
            TaskListContinuationPlan.make(
                in: text,
                editedRange: NSRange(location: 0, length: text.length),
                replacementText: "\n"
            )
        )
    }

    func testEmptyIndentedTaskPreservesIndentation() throws {
        let text = "    * [ ] " as NSString
        let plan = try XCTUnwrap(
            TaskListContinuationPlan.make(
                in: text,
                editedRange: NSRange(location: text.length, length: 0),
                replacementText: "\n"
            )
        )

        XCTAssertEqual(plan.replacement, "    ")
    }

    func testSlashTaskStateContinuesAsUncheckedTask() throws {
        let text = "- [/] partly done" as NSString
        let plan = try XCTUnwrap(
            TaskListContinuationPlan.make(
                in: text,
                editedRange: NSRange(location: text.length, length: 0),
                replacementText: "\n"
            )
        )

        XCTAssertEqual(plan.replacement, "\n- [ ] ")
    }
}
