import XCTest
@testable import Downward

final class AppSessionSettingsPresentationTests: XCTestCase {
    @MainActor
    func testRegularSettingsSurfaceKeepsCurrentEditorInUnderlyingDetail() {
        let session = AppSession()
        session.navigationLayout = .regular
        session.openDocument = PreviewSampleData.cleanDocument
        session.regularDetailSelection = .settings

        XCTAssertTrue(session.isShowingRegularSettingsSurface)
        XCTAssertEqual(
            session.regularWorkspaceDisplayDetail,
            .editor(PreviewSampleData.cleanDocument.url)
        )
    }

    @MainActor
    func testDismissingRegularSettingsSurfaceReturnsToOpenEditor() {
        let session = AppSession()
        session.navigationLayout = .regular
        session.openDocument = PreviewSampleData.dirtyDocument
        session.regularDetailSelection = .settings

        session.dismissRegularSettingsSurface()

        XCTAssertEqual(
            session.regularDetailSelection,
            .editor(PreviewSampleData.dirtyDocument.relativePath)
        )
    }

    @MainActor
    func testDismissingRegularSettingsSurfaceFallsBackToPendingEditorPresentation() {
        let session = AppSession()
        session.navigationLayout = .regular
        session.pendingEditorPresentation = .init(
            routeURL: PreviewSampleData.cleanDocument.url,
            relativePath: PreviewSampleData.cleanDocument.relativePath
        )
        session.regularDetailSelection = .settings

        session.dismissRegularSettingsSurface()

        XCTAssertEqual(
            session.regularDetailSelection,
            .editor(PreviewSampleData.cleanDocument.relativePath)
        )
    }

    @MainActor
    func testDismissingRegularSettingsSurfaceWithoutEditorFallsBackToPlaceholder() {
        let session = AppSession()
        session.navigationLayout = .regular
        session.regularDetailSelection = .settings

        session.dismissRegularSettingsSurface()

        XCTAssertEqual(session.regularDetailSelection, .placeholder)
    }
}
