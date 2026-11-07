import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if let s = app.speakingSession {
                SpeakingExamView(session: s)
                    .id(s.id)
            } else if let s = app.session {
                ExamView(session: s)
                    .environmentObject(s)
                    .id(s.id)
            } else {
                ShellView()
            }
        }
        .sheet(item: $app.speakingLaunch) { launch in
            SpeakingPreflightView(launch: launch)
        }
        .alert("提示", isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } })) {
            Button("好") { app.alert = nil }
        } message: {
            Text(app.alert ?? "")
        }
    }
}

struct ShellView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var bank: BankStore

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { app.route }, set: { if let r = $0 { app.navigate(r) } })) {
                Section("练习") {
                    Label("首页", systemImage: "house").tag(Route.home)
                    Label("题库", systemImage: "books.vertical").tag(Route.library)
                    Label("自定义题目", systemImage: "square.and.arrow.down").tag(Route.custom)
                }
                Section("复盘") {
                    Label("练习记录", systemImage: "clock.arrow.circlepath").tag(Route.history)
                    Label("错题本", systemImage: "exclamationmark.bubble").tag(Route.mistakes)
                    Label("写作记录", systemImage: "doc.text").tag(Route.writingLog)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if bank.loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("题库：\(bank.refs.filter { !$0.isCustom }.count) 套").font(.caption).foregroundStyle(.secondary)
                    }
                    SettingsLink { Label("设置", systemImage: "gearshape") }
                        .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
            NavigationStack(path: $app.path) {
                routeView
                    .navigationDestination(for: DetailPage.self) { page in
                        switch page {
                        case .book(let b): BookView(book: b)
                        case .test(let id): TestDetailView(examId: id)
                        case .attempt(let id): AttemptView(attemptId: id)
                        }
                    }
            }
        }
    }

    @ViewBuilder var routeView: some View {
        switch app.route {
        case .home: HomeView()
        case .library: LibraryView()
        case .history: HistoryView()
        case .mistakes: MistakesView()
        case .writingLog: WritingLogView()
        case .custom: CustomBankView()
        }
    }
}
