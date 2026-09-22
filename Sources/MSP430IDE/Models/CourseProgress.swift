import Foundation

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

    var id: String { concept + "|" + source }
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
    mutating func recordQuizResult(lesson: String, score: String, missed: [String], date: String) {
        var entry = lessons[lesson] ?? LessonProgress()
        entry.quiz = QuizProgress(status: "passed", score: score, date: date, missed: missed)
        lessons[lesson] = entry
    }
}

/// Reads/writes `progress/progress.json` at the root of the MSP430 handheld
/// firmware repo. This is the single structured source of truth shared
/// between Claude's grading workflow and the IDE's quiz results — see
/// firmware `CLAUDE.md`'s Grading rules.
enum CourseProgressStore {
    static let relativePath = "progress/progress.json"

    /// Marker file used to decide "this workspace is the course repo" before
    /// bothering to look for progress data at all.
    static func isCourseRepo(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("ROADMAP.md").path)
    }

    /// Never fails — a missing or unreadable file just means "no progress
    /// recorded yet," which is the normal state for an untouched lesson.
    static func load(workspaceRoot: URL) -> CourseProgress {
        let url = workspaceRoot.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return CourseProgress() }
        return (try? JSONDecoder().decode(CourseProgress.self, from: data)) ?? CourseProgress()
    }

    static func save(_ progress: CourseProgress, to workspaceRoot: URL) {
        let url = workspaceRoot.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(progress) {
            try? data.write(to: url)
        }
    }
}
