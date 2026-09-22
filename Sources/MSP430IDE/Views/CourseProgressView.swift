import SwiftUI

/// The "Course Progress" panel: which lessons/exercises/quizzes are done,
/// which concepts still need work, and buttons to pull/push
/// `progress/progress.json` in the open MSP430 handheld course repo.
struct CourseProgressView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let progress = appState.courseProgress {
                content(progress)
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "graduationcap")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Open the MSP430 handheld course repo to see progress")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ progress: CourseProgress) -> some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    lessonsSection(progress)
                    let gaps = unresolvedGaps(progress)
                    if !gaps.isEmpty {
                        gapsSection(gaps)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await appState.syncProgress() }
            } label: {
                Label("Pull Latest", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .help("Pull the latest progress.json from git")

            Button {
                Task { await appState.savePushProgress() }
            } label: {
                Label("Save & Push", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!appState.progressHasLocalChanges)
            .help(appState.progressHasLocalChanges
                  ? "Commit and push progress.json"
                  : "No local progress changes to push")

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func lessonsSection(_ progress: CourseProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lessons")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if progress.lessons.isEmpty {
                Text("No lessons started yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(progress.lessons.keys.sorted(), id: \.self) { slug in
                    if let lesson = progress.lessons[slug] {
                        lessonRow(slug: slug, lesson: lesson)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lessonRow(slug: String, lesson: LessonProgress) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(slug)
                .font(.callout.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(lesson.exercises.keys.sorted(), id: \.self) { exKey in
                    if let ex = lesson.exercises[exKey] {
                        statusBadge(label: exKey, status: ex.status, detail: ex.grade)
                    }
                }
                if let quiz = lesson.quiz {
                    statusBadge(label: "quiz", status: quiz.status, detail: quiz.score)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(label: String, status: String, detail: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: badgeIcon(for: status))
                .foregroundStyle(badgeColor(for: status))
            Text(label).font(.caption2)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func badgeIcon(for status: String) -> String {
        switch status {
        case "graded", "passed": return "checkmark.circle.fill"
        case "in_progress": return "circle.lefthalf.filled"
        default: return "circle"
        }
    }

    private func badgeColor(for status: String) -> Color {
        switch status {
        case "graded", "passed": return .green
        case "in_progress": return .orange
        default: return .secondary
        }
    }

    private func unresolvedGaps(_ progress: CourseProgress) -> [ConceptGap] {
        progress.conceptGaps.filter { !$0.resolved }
    }

    private func gapsSection(_ gaps: [ConceptGap]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Concepts needing work")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(gaps) { gap in
                VStack(alignment: .leading, spacing: 1) {
                    Text(gap.concept).font(.caption)
                    Text(gap.source).font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
