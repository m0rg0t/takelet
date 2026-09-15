import Foundation
import XCTest
import ProjectCore
@testable import TakeletApp

final class AnnotationWorkspaceTests: XCTestCase {
    private func annotation(
        _ kind: AnnotationKind = .arrow,
        start: Double = 1,
        end: Double = 3,
        text: String = "Callout"
    ) -> Annotation {
        Annotation(kind: kind, start: start, end: end, text: text)
    }

    private func project(
        annotations: [Annotation] = [],
        narrations: [NarrationSegment] = [],
        cuts: [TimeRange] = []
    ) -> Project {
        var project = Project(title: "Annotations", duration: 10, width: 1920, height: 1080)
        project.annotations = annotations
        project.narrations = narrations
        project.cuts = cuts
        return project
    }

    private func package(for project: Project) throws -> (directory: URL, source: URL) {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("takelet-annotation-source-\(UUID().uuidString).mov")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("takelet-annotation-save-\(UUID().uuidString).takelet")
        try Data("source".utf8).write(to: source)
        try ProjectStore.create(project, source: source, at: directory)
        return (directory, source)
    }

    @MainActor func testAddUsesSourcePositionAcrossCutAndNarrationHold() throws {
        let workspace = Workspace()
        defer { workspace.close() }
        let narration = NarrationSegment(
            start: 0,
            end: 1,
            script: "Long voiceover",
            voiceID: "voice",
            audioFile: "media/narration/\(UUID().uuidString).mp3",
            audioDuration: 3
        )
        workspace.project = project(
            narrations: [narration],
            cuts: [TimeRange(start: 2, end: 4)]
        )

        workspace.playhead = 2
        XCTAssertEqual(workspace.sourcePosition, 29.0 / 30, accuracy: 1e-9)
        workspace.addAnnotation(.arrow)

        let held = try XCTUnwrap(workspace.selectedAnnotation)
        XCTAssertEqual(workspace.selectedAnnotationID, held.id)
        XCTAssertEqual(held.start, 29.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(held.end, 2, accuracy: 1e-9)
        XCTAssertEqual(held.kind, .arrow)

        workspace.playhead = 4.5
        XCTAssertEqual(workspace.sourcePosition, 4.5, accuracy: 1e-9)
        workspace.addAnnotation(.cover)
        let afterCut = try XCTUnwrap(workspace.selectedAnnotation)
        XCTAssertEqual(afterCut.start, 4.5, accuracy: 1e-9)
        XCTAssertEqual(afterCut.end, 7.5, accuracy: 1e-9)
        XCTAssertEqual(afterCut.kind, .cover)
        XCTAssertEqual(afterCut.color, AnnotationColor(red: 0.08, green: 0.08, blue: 0.1))
    }

    @MainActor func testEditDuplicateAndRemoveAreUndoable() throws {
        let workspace = Workspace()
        defer { workspace.close() }
        let undo = UndoManager()
        undo.groupsByEvent = false
        workspace.undoManager = undo
        let original = annotation(bounds: AnnotationBounds(x: 0.2, y: 0.2, width: 0.3, height: 0.2))
        let initial = project(annotations: [original])
        workspace.project = initial
        workspace.selectedAnnotationID = original.id

        var edited = original
        edited.text = "Edited"
        edited.bounds = edited.bounds.translated(dx: 0.1, dy: 0.1)
        undo.beginUndoGrouping()
        XCTAssertTrue(workspace.updateAnnotation(edited))
        undo.endUndoGrouping()
        XCTAssertEqual(workspace.project?.annotations, [edited])
        undo.undo()
        XCTAssertEqual(workspace.project, initial)
        undo.redo()
        XCTAssertEqual(workspace.project?.annotations, [edited])

        var duplicateDraft = edited
        duplicateDraft.text = "Draft copied too"
        workspace.annotationDrafts[edited.id] = duplicateDraft
        undo.beginUndoGrouping()
        workspace.duplicateAnnotation(edited.id)
        undo.endUndoGrouping()
        let duplicatedProject = try XCTUnwrap(workspace.project)
        let duplicate = try XCTUnwrap(duplicatedProject.annotations.last)
        XCTAssertNotEqual(duplicate.id, edited.id)
        XCTAssertEqual(duplicate.text, duplicateDraft.text)
        XCTAssertEqual(duplicate.bounds, duplicateDraft.bounds.translated(dx: 0.03, dy: 0.03))
        XCTAssertEqual(workspace.selectedAnnotationID, duplicate.id)
        undo.undo()
        XCTAssertEqual(workspace.project?.annotations, [edited])
        undo.redo()
        XCTAssertEqual(workspace.project?.annotations.map(\.id), duplicatedProject.annotations.map(\.id))

        undo.beginUndoGrouping()
        workspace.removeAnnotation(duplicate.id)
        undo.endUndoGrouping()
        XCTAssertEqual(workspace.project?.annotations, [edited])
        XCTAssertNil(workspace.selectedAnnotationID)
        undo.undo()
        XCTAssertEqual(workspace.project?.annotations.map(\.id), duplicatedProject.annotations.map(\.id))
        undo.redo()
        XCTAssertEqual(workspace.project?.annotations, [edited])
    }

    @MainActor func testReorderMovesOnlyWithinLayerAndIsUndoable() {
        let workspace = Workspace()
        defer { workspace.close() }
        let undo = UndoManager()
        undo.groupsByEvent = false
        workspace.undoManager = undo
        let arrow = annotation(.arrow)
        let blur = annotation(.blur)
        let text = annotation(.text, text: "Text")
        let cover = annotation(.cover)
        let initial = project(annotations: [arrow, blur, text, cover])
        workspace.project = initial

        undo.beginUndoGrouping()
        workspace.moveAnnotation(arrow.id, forward: true)
        undo.endUndoGrouping()
        XCTAssertEqual(workspace.project?.annotations.map(\.id), [text.id, blur.id, arrow.id, cover.id])
        undo.undo()
        XCTAssertEqual(workspace.project, initial)
        undo.redo()
        XCTAssertEqual(workspace.project?.annotations.map(\.id), [text.id, blur.id, arrow.id, cover.id])

        undo.beginUndoGrouping()
        workspace.moveAnnotation(cover.id, forward: false)
        undo.endUndoGrouping()
        XCTAssertEqual(workspace.project?.annotations.map(\.id), [text.id, cover.id, arrow.id, blur.id])
        XCTAssertEqual(workspace.project?.annotations.filter { !$0.kind.isMask }.map(\.id), [text.id, arrow.id])
        XCTAssertEqual(workspace.project?.annotations.filter { $0.kind.isMask }.map(\.id), [cover.id, blur.id])
    }

    @MainActor func testDraftSurvivesSelectionAndSaveAtomicallyAppliesAllInspectorDrafts() throws {
        let workspace = Workspace()
        defer { workspace.close() }
        let undo = UndoManager()
        undo.groupsByEvent = false
        workspace.undoManager = undo
        let first = annotation(.text, start: 1, end: 3, text: "First")
        let second = annotation(.frame, start: 4, end: 6)
        let narration = NarrationSegment(start: 6, end: 8, script: "Old narration", voiceID: "voice")
        var initial = project(annotations: [first, second], narrations: [narration])
        initial.cursorMode = .separate
        let saved = try package(for: initial)
        defer {
            try? FileManager.default.removeItem(at: saved.source)
            try? FileManager.default.removeItem(at: saved.directory)
        }
        workspace.project = initial
        workspace.projectURL = saved.directory
        workspace.sourceURL = try ProjectStore.sourceURL(in: saved.directory)
        workspace.dirty = false
        workspace.selectedAnnotationID = first.id

        var annotationDraft = first
        annotationDraft.text = "Visible annotation draft"
        annotationDraft.bounds = annotationDraft.bounds.translated(dx: 0.12, dy: 0.08)
        workspace.annotationDrafts[first.id] = annotationDraft
        workspace.selectAnnotation(second.id)
        workspace.selectAnnotation(first.id)
        XCTAssertEqual(workspace.selectedAnnotationDraft, annotationDraft)
        XCTAssertTrue(workspace.dirty)

        var cursorDraft = initial.cursorStyle
        cursorDraft.size = 90
        workspace.cursorDraft = cursorDraft
        var narrationDraft = narration
        narrationDraft.script = "Visible narration draft"
        workspace.narrationDrafts[narration.id] = narrationDraft

        undo.beginUndoGrouping()
        workspace.saveProject()
        undo.endUndoGrouping()

        let persisted = try ProjectStore.load(from: saved.directory)
        XCTAssertEqual(persisted.annotations[0], annotationDraft)
        XCTAssertEqual(persisted.cursorStyle, cursorDraft)
        XCTAssertEqual(persisted.narrations[0].script, narrationDraft.script)
        XCTAssertTrue(workspace.annotationDrafts.isEmpty)
        XCTAssertNil(workspace.cursorDraft)
        XCTAssertTrue(workspace.narrationDrafts.isEmpty)
        XCTAssertFalse(workspace.dirty)

        undo.undo()
        XCTAssertEqual(workspace.project, initial)
        XCTAssertTrue(workspace.dirty)
        undo.redo()
        XCTAssertEqual(workspace.project, persisted)
        XCTAssertFalse(workspace.dirty)
    }

    @MainActor func testInvalidAnnotationDraftBlocksAtomicSaveAndLeavesPackageUntouched() throws {
        let workspace = Workspace()
        defer { workspace.close() }
        let callout = annotation(.text, text: "Original")
        let narration = NarrationSegment(start: 4, end: 6, script: "Original narration", voiceID: "voice")
        var initial = project(annotations: [callout], narrations: [narration])
        initial.cursorMode = .separate
        let saved = try package(for: initial)
        defer {
            try? FileManager.default.removeItem(at: saved.source)
            try? FileManager.default.removeItem(at: saved.directory)
        }
        workspace.project = initial
        workspace.projectURL = saved.directory
        workspace.sourceURL = try ProjectStore.sourceURL(in: saved.directory)

        var cursorDraft = initial.cursorStyle
        cursorDraft.size = 120
        workspace.cursorDraft = cursorDraft
        var narrationDraft = narration
        narrationDraft.script = "Must not partially apply"
        workspace.narrationDrafts[narration.id] = narrationDraft
        var invalidAnnotation = callout
        invalidAnnotation.bounds = AnnotationBounds(x: 0.9, y: 0.3, width: 0.4, height: 0.2)
        workspace.annotationDrafts[callout.id] = invalidAnnotation

        workspace.saveProject()

        XCTAssertEqual(workspace.project, initial)
        XCTAssertEqual(try ProjectStore.load(from: saved.directory), initial)
        XCTAssertEqual(workspace.cursorDraft, cursorDraft)
        XCTAssertEqual(workspace.narrationDrafts[narration.id], narrationDraft)
        XCTAssertEqual(workspace.annotationDrafts[callout.id], invalidAnnotation)
        XCTAssertNotNil(workspace.error)
        XCTAssertTrue(workspace.dirty)
    }

    @MainActor func testRemovePrunesOnlyTheRemovedAnnotationDraft() {
        let workspace = Workspace()
        defer { workspace.close() }
        let removed = annotation(.arrow, start: 1, end: 2)
        let kept = annotation(.text, start: 3, end: 4, text: "Keep")
        workspace.project = project(annotations: [removed, kept])
        workspace.selectedAnnotationID = removed.id
        var removedDraft = removed
        removedDraft.bounds = removedDraft.bounds.translated(dx: 0.1, dy: 0)
        var keptDraft = kept
        keptDraft.text = "Still pending"
        workspace.annotationDrafts = [removed.id: removedDraft, kept.id: keptDraft]

        workspace.removeAnnotation(removed.id)

        XCTAssertEqual(workspace.project?.annotations, [kept])
        XCTAssertNil(workspace.annotationDrafts[removed.id])
        XCTAssertEqual(workspace.annotationDrafts[kept.id], keptDraft)
        XCTAssertNil(workspace.selectedAnnotationID)
    }

    @MainActor func testUndoClearsDraftForChangedAnnotationButPreservesUnrelatedDraft() {
        let workspace = Workspace()
        defer { workspace.close() }
        let undo = UndoManager()
        undo.groupsByEvent = false
        workspace.undoManager = undo
        let first = annotation(.text, start: 1, end: 2, text: "First")
        let second = annotation(.frame, start: 3, end: 4)
        workspace.project = project(annotations: [first, second])

        var committedFirst = first
        committedFirst.text = "Committed edit"
        undo.beginUndoGrouping()
        XCTAssertTrue(workspace.updateAnnotation(committedFirst))
        undo.endUndoGrouping()

        var firstDraft = committedFirst
        firstDraft.text = "Pending edit on changed annotation"
        var secondDraft = second
        secondDraft.bounds = secondDraft.bounds.translated(dx: 0.1, dy: 0.1)
        workspace.annotationDrafts = [first.id: firstDraft, second.id: secondDraft]

        undo.undo()

        XCTAssertEqual(workspace.project?.annotations, [first, second])
        XCTAssertNil(workspace.annotationDrafts[first.id])
        XCTAssertEqual(workspace.annotationDrafts[second.id], secondDraft)
        undo.redo()
        XCTAssertEqual(workspace.project?.annotations, [committedFirst, second])
        XCTAssertEqual(workspace.annotationDrafts[second.id], secondDraft)
    }

    @MainActor func testAnnotationActionsAreBlockedDuringExportAndNarrationGeneration() {
        let workspace = Workspace()
        defer { workspace.close() }
        let first = annotation(.arrow, start: 1, end: 2)
        let second = annotation(.frame, start: 3, end: 4)
        let initial = project(annotations: [first, second])
        workspace.project = initial
        var edited = first
        edited.bounds = edited.bounds.translated(dx: 0.1, dy: 0.1)

        func exerciseBlockedActions() {
            workspace.addAnnotation(.cover)
            XCTAssertFalse(workspace.updateAnnotation(edited))
            workspace.duplicateAnnotation(first.id)
            workspace.moveAnnotation(first.id, forward: true)
            workspace.removeAnnotation(first.id)
            workspace.selectAnnotation(first.id)
        }

        workspace.exporting = true
        exerciseBlockedActions()
        XCTAssertEqual(workspace.project, initial)
        XCTAssertNil(workspace.selectedAnnotationID)

        workspace.exporting = false
        workspace.generatingNarrationID = UUID()
        exerciseBlockedActions()
        XCTAssertEqual(workspace.project, initial)
        XCTAssertNil(workspace.selectedAnnotationID)
    }
}

private extension AnnotationWorkspaceTests {
    func annotation(
        bounds: AnnotationBounds,
        kind: AnnotationKind = .arrow,
        start: Double = 1,
        end: Double = 3
    ) -> Annotation {
        Annotation(kind: kind, start: start, end: end, bounds: bounds)
    }
}
