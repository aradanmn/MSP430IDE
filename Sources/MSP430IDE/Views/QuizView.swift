import SwiftUI

private struct QuizQuestion {
    let id: Int
    let prompt: String
    let choices: [String]
    let answer: Int
    let explain: String
}

/// Renders a lesson's `quiz.toml` as a self-graded, one-question-at-a-time
/// concept check. Opened in place of the raw text/markdown view when a
/// `quiz.toml` file is selected (see `MainView.EditorPaneContent`). Distinct
/// from Ex1-3 exercises: no hardware, no file output, answer key included —
/// see firmware CLAUDE.md's Exercise Format Policy, "Quiz" row.
struct QuizView: View {
    @ObservedObject var buffer: TextBuffer
    @EnvironmentObject var appState: AppState

    @State private var questions: [QuizQuestion] = []
    @State private var lessonSlug = ""
    @State private var parseError: String?
    @State private var currentIndex = 0
    @State private var selectedChoice: Int?
    @State private var checked = false
    @State private var missedPrompts: [String] = []
    @State private var finished = false

    var body: some View {
        Group {
            if let parseError {
                errorState(parseError)
            } else if questions.isEmpty {
                Color.clear
            } else if finished {
                scoreScreen
            } else {
                questionScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear(perform: parseIfNeeded)
    }

    // MARK: - Parsing

    private func parseIfNeeded() {
        guard questions.isEmpty, parseError == nil else { return }
        do {
            let root = try TOMLParser.parse(buffer.text)
            guard let quizTable = root["quiz"]?.tableValue else {
                parseError = "No [quiz] table found in this file."
                return
            }
            lessonSlug = quizTable["lesson"]?.stringValue ?? ""
            let rawQuestions = quizTable["questions"]?.arrayValue ?? []
            questions = rawQuestions.compactMap { item -> QuizQuestion? in
                guard let t = item.tableValue,
                      let id = t["id"]?.intValue,
                      let prompt = t["prompt"]?.stringValue,
                      let choices = t["choices"]?.stringArray,
                      let answer = t["answer"]?.intValue,
                      let explain = t["explain"]?.stringValue else { return nil }
                return QuizQuestion(id: id, prompt: prompt, choices: choices, answer: answer, explain: explain)
            }
            if questions.isEmpty {
                parseError = "No valid questions found in this quiz file."
            }
        } catch {
            parseError = "Couldn't parse quiz.toml: \(error.localizedDescription)"
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Question screen

    private var current: QuizQuestion { questions[currentIndex] }

    private var questionScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Question \(currentIndex + 1) of \(questions.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(current.prompt)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(current.choices.enumerated()), id: \.offset) { idx, choice in
                    choiceRow(idx: idx, choice: choice)
                }
            }

            if checked {
                explanationBox
            }

            HStack {
                Spacer()
                if !checked {
                    Button("Check") { check() }
                        .disabled(selectedChoice == nil)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(currentIndex == questions.count - 1 ? "See Score" : "Next") { advance() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func choiceRow(idx: Int, choice: String) -> some View {
        let isSelected = selectedChoice == idx
        let isCorrectChoice = idx == current.answer
        return Button {
            guard !checked else { return }
            selectedChoice = idx
        } label: {
            HStack(spacing: 10) {
                Image(systemName: radioIcon(isSelected: isSelected, isCorrectChoice: isCorrectChoice))
                    .foregroundStyle(radioColor(isSelected: isSelected, isCorrectChoice: isCorrectChoice))
                Text(choice)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(rowBackground(isSelected: isSelected, isCorrectChoice: isCorrectChoice))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(checked)
    }

    private func radioIcon(isSelected: Bool, isCorrectChoice: Bool) -> String {
        if checked {
            if isCorrectChoice { return "checkmark.circle.fill" }
            if isSelected { return "xmark.circle.fill" }
            return "circle"
        }
        return isSelected ? "circle.fill" : "circle"
    }

    private func radioColor(isSelected: Bool, isCorrectChoice: Bool) -> Color {
        if checked {
            if isCorrectChoice { return .green }
            if isSelected { return .red }
            return .secondary
        }
        return isSelected ? .accentColor : .secondary
    }

    private func rowBackground(isSelected: Bool, isCorrectChoice: Bool) -> Color {
        if checked && isCorrectChoice { return Color.green.opacity(0.12) }
        if checked && isSelected { return Color.red.opacity(0.10) }
        if !checked && isSelected { return Color.accentColor.opacity(0.10) }
        return Color.clear
    }

    private var explanationBox: some View {
        let isCorrect = selectedChoice == current.answer
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: isCorrect ? "checkmark.seal.fill" : "info.circle.fill")
                .foregroundStyle(isCorrect ? Color.green : Color.orange)
            Text(current.explain)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func check() {
        checked = true
        if selectedChoice != current.answer {
            missedPrompts.append(current.prompt)
        }
    }

    private func advance() {
        if currentIndex == questions.count - 1 {
            finished = true
        } else {
            currentIndex += 1
            selectedChoice = nil
            checked = false
        }
    }

    // MARK: - Score screen

    private var scoreScreen: some View {
        let correct = questions.count - missedPrompts.count
        return VStack(spacing: 14) {
            Image(systemName: missedPrompts.isEmpty ? "star.fill" : "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(missedPrompts.isEmpty ? Color.yellow : Color.accentColor)
            Text("\(correct) / \(questions.count)")
                .font(.largeTitle.weight(.bold))
            if !missedPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Worth revisiting:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(missedPrompts, id: \.self) { prompt in
                        Text("• \(prompt)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
            Text("Saved to progress.json locally. Use the Course Progress panel to push it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: recordResult)
    }

    private func recordResult() {
        guard let root = appState.workspaceRoot, !lessonSlug.isEmpty else { return }
        let correct = questions.count - missedPrompts.count
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var progress = CourseProgressStore.load(workspaceRoot: root)
        progress.recordQuizResult(
            lesson: lessonSlug,
            score: "\(correct)/\(questions.count)",
            missed: missedPrompts,
            date: df.string(from: Date())
        )
        CourseProgressStore.save(progress, to: root)
        appState.reloadCourseProgress()
    }
}
