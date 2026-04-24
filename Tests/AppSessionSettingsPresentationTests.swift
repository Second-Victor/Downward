import XCTest
@testable import Downward

final class AppSessionSettingsPresentationTests: XCTestCase {
    @MainActor
    func testSettingsSurfacePresentsAsSheetFlag() {
        let session = AppSession()

        session.isSettingsPresented = true

        XCTAssertTrue(session.isSettingsPresented)
    }

    @MainActor
    func testRegularSettingsSurfaceKeepsCurrentEditorInUnderlyingDetail() {
        let session = AppSession()
        session.navigationLayout = .regular
        session.openDocument = PreviewSampleData.cleanDocument
        session.regularDetailSelection = .editor(PreviewSampleData.cleanDocument.relativePath)
        session.isSettingsPresented = true

        XCTAssertTrue(session.isShowingRegularSettingsSurface)
        XCTAssertEqual(
            session.regularWorkspaceDisplayDetail,
            .editor(PreviewSampleData.cleanDocument.url)
        )
    }

    @MainActor
    func testDismissingSettingsSurfaceKeepsUnderlyingEditorSelection() {
        let session = AppSession()
        session.navigationLayout = .regular
        session.openDocument = PreviewSampleData.dirtyDocument
        session.regularDetailSelection = .editor(PreviewSampleData.dirtyDocument.relativePath)
        session.isSettingsPresented = true

        session.dismissSettingsSurface()

        XCTAssertFalse(session.isSettingsPresented)
        XCTAssertEqual(
            session.regularDetailSelection,
            .editor(PreviewSampleData.dirtyDocument.relativePath)
        )
    }

    @MainActor
    func testDismissingSettingsSurfaceWithoutEditorKeepsPlaceholder() {
        let session = AppSession()
        session.navigationLayout = .regular
        session.regularDetailSelection = .placeholder
        session.isSettingsPresented = true

        session.dismissSettingsSurface()

        XCTAssertFalse(session.isSettingsPresented)
        XCTAssertEqual(session.regularDetailSelection, .placeholder)
    }
}
