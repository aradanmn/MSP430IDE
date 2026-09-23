import Foundation
import SwiftUI

/// Shared status categorization, used by both the Course Progress panel and
/// the file-tree badges so the two can't silently disagree on what a status
/// string means (they previously each hand-rolled this switch, and neither
/// knew about "failed"). Each view still picks its own glyph — a bare
/// `Image` in the panel vs. a tiny 7pt dot already inside a filled circle
/// in the tree — since a full `checkmark.circle.fill` doesn't read well
/// nested inside another circle badge.
enum ProgressStatus {
    enum Category { case done, failed, inProgress, none }

    static func category(for status: String?) -> Category {
        switch status {
        case "graded", "passed": return .done
        case "failed": return .failed
        case "in_progress": return .inProgress
        default: return .none
        }
    }

    /// Full-size icon for standalone use (e.g. the Course Progress panel).
    static func icon(for status: String?) -> String {
        switch category(for: status) {
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .inProgress: return "circle.lefthalf.filled"
        case .none: return "circle"
        }
    }

    static func color(for status: String?) -> Color {
        switch category(for: status) {
        case .done: return .green
        case .failed: return .red
        case .inProgress: return .orange
        case .none: return .secondary
        }
    }
}

struct ExerciseProgress: Codable, Equatable {
    var status: String
    var grade: String?
    var date: String?
    var notes: String?
}

struct QuizProgress: Codable, Equatable {
    var status: String
    var score: String?
    var date: String?
    var missed: [String] = []
}

struct LessonProgress: Codable, Equatable {
    var exercises: [String: ExerciseProgress] = [:]
    var quiz: QuizProgress?
}

struct ConceptGap: Codable, Equatable, Identifiable {
    var concept: String
    var source: String
    var date: String
    var resolved: Bool = false

    // Includes `date` so a recurring gap (same concept/source logged again
    // on a later date, e.g. a repeat mistake) gets its own id instead of
    // colliding with the earlier entry and being dropped by SwiftUI's
    // ForEach/List identity tracking.
    var id: String { concept + "|" + source + "|" + date }
}

struct CourseProgress: Codable, Equatable {
    var lessons: [String: LessonProgress] = [:]
    var conceptGaps: [ConceptGap] = []

    enum CodingKeys: String, CodingKey {
        case lessons
        case conceptGaps = "concept_gaps"
    }
}

extension CourseProgress {
    /// Records a completed quiz attempt for `lesson`, overwriting any prior
    /// attempt (retakes are allowed and expected — see CLAUDE.md's Quiz tier).
    /// Status reflects whether anything was actually missed — a quiz with
    /// every question wrong is "failed", not "passed".
    mutating func recordQuizResult(lesson: String, score: String, missed: [String], date: String) {
        var entry = lessons[lesson] ?? LessonProgress()
        let status = missed.isEmpty ? "passed" : "failed"
        entry.quiz = QuizProgress(status: status, score: score, date: date, missed: missed)
        lessons[lesson] = entry
    }
}

/// Reads/writes `progress/progress.json` at the root of the MSP430 handheld
/// firmware repo. This is the single structured source of truth shared
/// between Claude's grading workflow and the IDE's quiz results — see
/// firmware `CLAUDE.md`'s Grading rules.
enum CourseProgressStore {
    static let relativePath = "progress/progress.json"

    enum LoadResult {
        case notFound
        case loaded(CourseProgress)
        /// The file exists but couldn't be decoded (mid `git pull` merge
        /// conflict, schema drift, hand-edit typo, etc.) — distinct from
        /// `.notFound` so a writer can refuse to silently overwrite it.
        case corrupted(Error)
    }

    /// Marker used to decide "this workspace is the course repo" before
    /// bothering to look for progress data, or wiring up live git actions.
    /// Requires both `ROADMAP.md` and a `course/` directory at the root —
    /// `ROADMAP.md` alone is too generic a filename to gate real git
    /// pull/push actions on.
    static func isCourseRepo(_ root: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let hasCourseDir = fm.fileExists(atPath: root.appendingPathComponent("course").path, isDirectory: &isDir) && isDir.boolValue
        return hasCourseDir && fm.fileExists(atPath: root.appendingPathComponent("ROADMAP.md").path)
    }

    static func loadResult(workspaceRoot: URL) -> LoadResult {
        let url = workspaceRoot.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return .notFound }
        do {
            return .loaded(try JSONDecoder().decode(CourseProgress.self, from: data))
        } catch {
            return .corrupted(error)
        }
    }

    /// Never fails — a missing OR corrupted file both read as "no progress"
    /// for display purposes (the Course Progress panel already has an empty
    /// state). Do not use this for a write path that then saves back over
    /// the file — use `loadResult` there so corruption isn't silently
    /// clobbered. See `QuizView.recordResult`.
    static func load(workspaceRoot: URL) -> CourseProgress {
        switch loadResult(workspaceRoot: workspaceRoot) {
        case .notFound, .corrupted: return CourseProgress()
        case .loaded(let progress): return progress
        }
    }

    @discardableResult
    static func save(_ progress: CourseProgress, to workspaceRoot: URL) -> Bool {
        let url = workspaceRoot.appendingPathComponent(relativePath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(progress)
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
