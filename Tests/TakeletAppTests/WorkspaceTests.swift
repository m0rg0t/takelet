import Foundation
import XCTest
import ProjectCore
@testable import TakeletApp

final class WorkspaceTests: XCTestCase {
    @MainActor func testAutoZoomIsOneUndoableEditAndRedoRestoresIDs() {
        let workspace = Workspace(); defer { workspace.close() }
        let undo = UndoManager(); undo.groupsByEvent = false; workspace.undoManager = undo
        var initial = Project(title: "Clicks", duration: 10, width: 1920, height: 1080)
        initial.cursor = [CursorSample(time: 1, x: 0.2, y: 0.3, visible: true, pressed: true),
                          CursorSample(time: 2, x: 0.2, y: 0.3, visible: true, pressed: false),
                          CursorSample(time: 6, x: 0.8, y: 0.7, visible: true, pressed: true)]
        workspace.project = initial
        undo.beginUndoGrouping(); workspace.generateClickZooms(); undo.endUndoGrouping()
        let edited = workspace.project
        XCTAssertEqual(edited?.zooms.count, 2)
        XCTAssertEqual(undo.undoActionName, "Auto Zoom from Clicks")
        undo.undo()
        XCTAssertEqual(workspace.project, initial)
        undo.redo()
        XCTAssertEqual(workspace.project, edited)
        workspace.generateClickZooms()
        XCTAssertEqual(workspace.project, edited)
        undo.undo()
        XCTAssertEqual(workspace.project, initial) // The repeated action did not add another undo step.
    }

    @MainActor func testEditingAndDeletingOneZoomPreservesTheOther() {
        let workspace = Workspace(); defer { workspace.close() }
        let undo = UndoManager(); undo.groupsByEvent = false; workspace.undoManager = undo
        var initial = Project(title: "Focus", duration: 10, width: 1920, height: 1080)
        initial.zooms = [Zoom(start: 0, end: 2), Zoom(start: 5, end: 8)]
        workspace.project = initial; workspace.selectedZoomID = initial.zooms[1].id
        var changed = initial.zooms[1]; changed.scale = 2.8; changed.x = 0.9
        undo.beginUndoGrouping(); workspace.updateZoom(changed); undo.endUndoGrouping()
        XCTAssertEqual(workspace.project?.zooms, [initial.zooms[0], changed])
        var overlapping = changed; overlapping.start = 1
        workspace.updateZoom(overlapping)
        XCTAssertNotNil(workspace.error)
        XCTAssertEqual(workspace.project?.zooms, [initial.zooms[0], changed])
        undo.beginUndoGrouping(); workspace.removeZoom(changed.id); undo.endUndoGrouping()
        XCTAssertNil(workspace.selectedZoomID)
        XCTAssertEqual(workspace.project?.zooms, [initial.zooms[0]])
        undo.undo()
        XCTAssertEqual(workspace.project?.zooms, [initial.zooms[0], changed])
        undo.undo()
        XCTAssertEqual(workspace.project, initial)
    }

    @MainActor func testAddZoomUsesOutputToSourceMappingAndCannotEditDuringExport() {
        let workspace = Workspace(); defer { workspace.close() }
        var initial = Project(title: "Cut", duration: 10, width: 1920, height: 1080)
        initial.cuts = [TimeRange(start: 1, end: 3)]
        workspace.project = initial; workspace.playhead = 2
        workspace.addZoom()
        XCTAssertEqual(workspace.project?.zooms.first?.start, 4)
        XCTAssertEqual(workspace.project?.zooms.first?.end, 6)
        XCTAssertEqual(workspace.selectedZoomID, workspace.project?.zooms.first?.id)
        let edited = workspace.project
        workspace.exporting = true
        workspace.addZoom(); workspace.generateClickZooms()
        if let id = workspace.selectedZoomID { workspace.removeZoom(id) }
        XCTAssertEqual(workspace.project, edited)
    }
}
