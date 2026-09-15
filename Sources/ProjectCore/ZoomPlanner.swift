import Foundation

/// Local, editable zooms based on source time. Never modifies existing zooms or cuts.
public enum ZoomPlanner {
    public static func manualZoom(in project: Project, at time: Double) -> Zoom? {
        guard time.isFinite, project.zooms.count < 512,
              let space = freeRange(in: project, at: time, occupied: project.zooms), space.duration >= 0.1 else { return nil }
        let start = min(time, max(space.start, space.end - 0.4))
        return Zoom(start: start, end: min(space.end, start + 2))
    }

    /// A sampled mouse-down edge creates one focus interval. Held buttons and clicks
    /// inside cuts or existing zooms are ignored; nearby clicks share the first zoom.
    public static func clickZooms(in project: Project) -> [Zoom] {
        var additions: [Zoom] = []
        var pressed = false
        for sample in project.cursor {
            let mouseDown = sample.pressed && !pressed
            pressed = sample.pressed
            guard mouseDown, sample.visible, (0...1).contains(sample.x), (0...1).contains(sample.y),
                  project.zooms.count + additions.count < 512,
                  let space = freeRange(in: project, at: sample.time, occupied: project.zooms + additions) else { continue }
            let start = max(space.start, sample.time - 0.4)
            let end = min(space.end, sample.time + 1.2)
            guard end - start >= 0.8 else { continue }
            additions.append(Zoom(start: start, end: end, x: sample.x, y: sample.y))
        }
        return additions
    }

    private static func freeRange(in project: Project, at time: Double, occupied: [Zoom]) -> TimeRange? {
        guard let kept = project.retainedRanges.first(where: { time >= $0.start && time < $0.end }),
              !occupied.contains(where: { time >= $0.start && time < $0.end }) else { return nil }
        let start = occupied.filter { $0.end <= time }.map(\.end).max() ?? 0
        let end = occupied.filter { $0.start > time }.map(\.start).min() ?? project.sourceDuration
        return TimeRange(start: max(kept.start, start), end: min(kept.end, end))
    }
}
