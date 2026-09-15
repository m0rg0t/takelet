import Foundation
import ProjectCore

extension Workspace {
    var selectedAnnotation: Annotation? { project?.annotations.first { $0.id == selectedAnnotationID } }
    var selectedAnnotationDraft: Annotation? {
        guard let selectedAnnotation else { return nil }
        return annotationDrafts[selectedAnnotation.id] ?? selectedAnnotation
    }

    func addAnnotation(_ kind: AnnotationKind) {
        guard canEdit, var next = project else { return }
        guard next.annotations.count < 64 else { error = "A project supports up to 64 callouts and masks."; return }
        let position = sourcePosition
        guard let retained = next.retainedRanges.first(where: { $0.end > position }) else { return }
        let start = max(position, retained.start)
        let end = min(start + 3, retained.end)
        guard end - start >= 1.0 / 30 else { status = "Choose a longer uncut interval for the annotation."; return }
        var annotation = Annotation(kind: kind, start: start, end: end)
        if kind == .cover { annotation.color = AnnotationColor(red: 0.08, green: 0.08, blue: 0.1) }
        if kind == .text { annotation.color = AnnotationColor(red: 0.27, green: 0.23, blue: 0.48) }
        next.annotations.append(annotation)
        if edit(next, name: "Add \(kind.title)") {
            selectedAnnotationID = annotation.id
            player.pause(); isPlaying = false
            status = "\(kind.title) added. Set its timing, then choose Place on Frame to position it."
        }
    }

    func selectAnnotation(_ id: UUID) {
        guard canEdit, let annotation = project?.annotations.first(where: { $0.id == id }) else { return }
        selectedAnnotationID = id
        player.pause(); isPlaying = false
        seekSource(annotation.start)
    }

    @discardableResult func updateAnnotation(_ annotation: Annotation) -> Bool {
        guard canEdit, var next = project,
              let index = next.annotations.firstIndex(where: { $0.id == annotation.id }) else { return false }
        next.annotations[index] = annotation
        do { try next.validate() } catch { self.error = error.localizedDescription; return false }
        if next != project, !edit(next, name: "Edit \(annotation.kind.title)") { return false }
        annotationDrafts.removeValue(forKey: annotation.id)
        return true
    }

    func removeAnnotation(_ id: UUID) {
        guard canEdit, var next = project else { return }
        next.annotations.removeAll { $0.id == id }
        edit(next, name: "Remove Annotation")
    }

    func duplicateAnnotation(_ id: UUID) {
        guard canEdit, var next = project,
              var annotation = annotationDrafts[id] ?? next.annotations.first(where: { $0.id == id }) else { return }
        annotation.id = UUID()
        annotation.bounds = annotation.bounds.translated(dx: 0.03, dy: 0.03)
        next.annotations.append(annotation)
        if edit(next, name: "Duplicate Annotation") { selectedAnnotationID = annotation.id }
    }

    /// Change order only within the same layer. Masks always cover callouts.
    func moveAnnotation(_ id: UUID, forward: Bool) {
        guard canEdit, var next = project,
              let index = next.annotations.firstIndex(where: { $0.id == id }) else { return }
        let matching = next.annotations.indices.filter {
            next.annotations[$0].kind.isMask == next.annotations[index].kind.isMask && (forward ? $0 > index : $0 < index)
        }
        guard let destination = forward ? matching.first : matching.last else { return }
        next.annotations.swapAt(index, destination)
        edit(next, name: "Reorder Annotation")
    }
}
