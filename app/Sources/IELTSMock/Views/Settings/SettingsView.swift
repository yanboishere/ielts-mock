import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AISettingsTab().tabItem { Label("AI", systemImage: "sparkles") }
            TimingSettingsTab().tabItem { Label("计时与提醒", systemImage: "timer") }
            SpeakingSettingsTab().tabItem { Label("口语", systemImage: "mic") }
            BankSettingsTab().tabItem { Label("题库", systemImage: "books.vertical") }
            DisplaySettingsTab().tabItem { Label("显示", systemImage: "textformat") }
        }
        .frame(width: 680, height: 600)
    }
}

struct AISettingsTab: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var ai: AIService
    @State private var claudeKey = ""
    @State private var openaiKey = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var customClaude = false
    @State private var customOpenAI = false

    var body: some View {
        Form {
            Section {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(AIProviderKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("BYOK：使用你自己的 API Key。Key 只保存在本机「钥匙串」，请求直接从本机发往服务商（会走系统代理设置）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if settings.provider == .claude {
                Section("Claude") {
                    SecureField("API Key（sk-ant-…）", text: $claudeKey)
                        .onSubmit { settings.setAPIKey(claudeKey, for: .claude) }
                    modelPicker(selection: $settings.claudeModel, options: SettingsStore.claudeModels, custom: $customClaude)
                    TextField("Base URL", text: $settings.claudeBaseURL)
                    Toggle("启用服务端拒答回退（fallbacks: \"default\"，仅官方 API）", isOn: $settings.claudeFallbacks)
                    Text("默认模型 claude-opus-5-5；如需更快更省可选 claude-sonnet-5-5 / claude-haiku-5-5。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("OpenAI") {
                    SecureField("API Key（sk-…）", text: $openaiKey)
                        .onSubmit { settings.setAPIKey(openaiKey, for: .openai) }
                    modelPicker(selection: $settings.openaiModel, options: SettingsStore.openaiModels, custom: $customOpenAI)
                    TextField("Base URL", text: $settings.openaiBaseURL)
                    Text("也可以填写兼容 OpenAI Chat Completions 接口的第三方地址（如 https://xxx/v1）。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("输出") {
                Picker("解析语言", selection: $settings.aiLanguage) {
                    Text("简体中文").tag("zh")
                    Text("English").tag("en")
                }
                Picker("错题解析推理强度", selection: $settings.explainEffort) {
                    Text("low").tag("low"); Text("medium").tag("medium"); Text("high").tag("high")
                }
                Picker("写作评分推理强度", selection: $settings.writingEffort) {
                    Text("low").tag("low"); Text("medium").tag("medium"); Text("high").tag("high")
                }
            }
            Section {
                HStack {
                    Button("保存 Key") {
                        if !claudeKey.isEmpty { settings.setAPIKey(claudeKey, for: .claude) }
                        if !openaiKey.isEmpty { settings.setAPIKey(openaiKey, for: .openai) }
                        claudeKey = ""
                        openaiKey = ""
                        testResult = "已保存到钥匙串。"
                    }
                    Button("测试连接") {
                        if !claudeKey.isEmpty { settings.setAPIKey(claudeKey, for: .claude); claudeKey = "" }
                        if !openaiKey.isEmpty { settings.setAPIKey(openaiKey, for: .openai); openaiKey = "" }
                        testing = true
                        testResult = nil
                        Task {
                            do { testResult = try await ai.testConnection() } catch { testResult = "失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription) }
                            testing = false
                        }
                    }
                    .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("删除当前服务商的 Key", role: .destructive) { settings.setAPIKey("", for: settings.provider); testResult = "已删除。" }
                }
                Text(settings.hasKeyForCurrentProvider ? "✓ 已配置 \(settings.provider.label) 的 Key" : "尚未配置 \(settings.provider.label) 的 Key")
                    .font(.caption).foregroundStyle(settings.hasKeyForCurrentProvider ? Theme.correct : .secondary)
                if let r = testResult { Text(r).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            customClaude = !SettingsStore.claudeModels.contains(settings.claudeModel)
            customOpenAI = !SettingsStore.openaiModels.contains(settings.openaiModel)
        }
    }

    @ViewBuilder func modelPicker(selection: Binding<String>, options: [String], custom: Binding<Bool>) -> some View {
        if custom.wrappedValue {
            HStack {
                TextField("模型名称", text: selection)
                Button("从列表选择") { custom.wrappedValue = false; if !options.contains(selection.wrappedValue) { selection.wrappedValue = options[0] } }
            }
        } else {
            HStack {
                Picker("模型", selection: selection) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                Button("自定义…") { custom.wrappedValue = true }
            }
        }
    }
}

struct TimingSettingsTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var reminderText = ""

    var body: some View {
        Form {
            Section("时长") {
                Stepper("阅读：\(settings.readingMinutes) 分钟", value: $settings.readingMinutes, in: 20...120, step: 5)
                Stepper("写作：\(settings.writingMinutes) 分钟", value: $settings.writingMinutes, in: 20...120, step: 5)
                Picker("听力检查时间", selection: $settings.listeningReviewMinutes) {
                    Text("2 分钟（机考）").tag(2)
                    Text("10 分钟（纸笔考誊写时间）").tag(10)
                    Text("不留检查时间").tag(0)
                }
                Text("单篇阅读练习固定 20 分钟；单项写作练习按题目建议时长（Task 1 20 分钟，Task 2 40 分钟）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("提醒") {
                TextField("剩余多少分钟时提醒（逗号分隔）", text: $reminderText)
                    .onSubmit(applyReminders)
                    .onChange(of: reminderText) { _, _ in applyReminders() }
                Toggle("提示音", isOn: $settings.reminderSound)
                Toggle("App 在后台时发送系统通知", isOn: $settings.reminderNotification)
                Toggle("阅读模考：20/40 分钟时提醒切换下一篇", isOn: $settings.readingPassageNudge)
                Toggle("写作模考：20 分钟时提醒开始 Task 2", isOn: $settings.writingTaskNudge)
            }
            Section("交卷") {
                Toggle("时间到自动交卷（模考始终自动交卷）", isOn: $settings.autoSubmit)
                Toggle("听力播放到下一 Part 时自动翻页", isOn: $settings.autoAdvanceListening)
            }
        }
        .formStyle(.grouped)
        .onAppear { reminderText = settings.reminderMinutes.map(String.init).joined(separator: ", ") }
    }

    func applyReminders() {
        let v = reminderText.split { $0 == "," || $0 == "，" || $0 == " " }.compactMap { Int($0) }.filter { $0 > 0 && $0 < 120 }
        if !v.isEmpty { settings.reminderMinutes = Array(Set(v)).sorted(by: >) }
    }
}

struct BankSettingsTab: View {
    @EnvironmentObject var bank: BankStore
    @EnvironmentObject var app: AppState
    @State private var choosing = false

    var body: some View {
        Form {
            Section("题库位置") {
                Text(bank.bankRoot.path).font(.callout.monospaced()).textSelection(.enabled)
                HStack {
                    Button("选择题库文件夹…") { choosing = true }
                    Button("恢复默认位置") { bank.bankPath = ""; bank.reload() }
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([bank.bankRoot]) }
                    Button("重新载入") { bank.reload() }
                }
                Text("题库文件夹需包含 exams/（每套题一个 JSON），以及 images/、audio/、pages/。默认位置：~/Library/Application Support/IELTSMock/Bank")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("状态") {
                Text("已载入 \(bank.refs.filter { !$0.isCustom }.count) 套真题，\(bank.customRefs.count) 套自定义题目")
                let missing = bank.refs.filter { !$0.missingAudioParts.isEmpty }
                if !missing.isEmpty {
                    Text("缺少部分听力音频：" + missing.map { "\($0.exam.shortTitle)（Part \($0.missingAudioParts.map { String($0 + 1) }.joined(separator: ","))）" }.joined(separator: "、"))
                        .font(.caption).foregroundStyle(.orange)
                }
                if let e = bank.lastError { Text(e).font(.caption).foregroundStyle(.red) }
            }
            Section("版权提示") {
                Text("剑桥雅思真题的文字、音频与图片版权归 Cambridge University Press & Assessment 所有，仅供个人学习使用，请勿公开传播题库文件。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { r in
            if case .success(let url) = r {
                bank.bankPath = url.path
                bank.reload()
            }
        }
    }
}

struct DisplaySettingsTab: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Section("考试界面") {
                Slider(value: $settings.fontScale, in: 0.8...1.6, step: 0.1) { Text("字号 \(Int(settings.fontScale * 100))%") }
                TextField("考生姓名（显示在考试顶栏，可留空）", text: $settings.candidateName)
            }
        }
        .formStyle(.grouped)
    }
}

struct SpeakingSettingsTab: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var models: SpeechModelStore
    @StateObject private var examiner = Examiner()

    var body: some View {
        Form {
            Section("本地语音识别（Arion 同款模型）") {
                ForEach(SpeechCatalog.all) { spec in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(spec.title).bold()
                            Spacer()
                            if models.state(spec) == .ready {
                                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([models.fileURL(spec)]) }
                                Button("删除", role: .destructive) { models.delete(spec) }
                            }
                        }
                        ModelStatusView(spec: spec)
                    }
                }
                Toggle("从国内镜像下载（hf-mirror.com）", isOn: $settings.modelMirror)
                LabeledContent("语音引擎") {
                    Text(SpeechEngine.binary.map { "speech.cpp 0.8.11（\($0.path.contains(".app/") ? "已内置" : $0.path)）" } ?? "未找到")
                        .foregroundStyle(SpeechEngine.binary == nil ? .red : .secondary)
                }
                Text("模型在本机运行（Apple Silicon 上用 Metal 加速），录音不离开电脑。模型来自 Qwen3-ASR（Apache-2.0），推理引擎 speech.cpp（MIT），与 AstraFoundry/Arion 选用的组合相同。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("考官") {
                Picker("声音", selection: $settings.examinerVoice) {
                    Text("自动（最佳英式声音）").tag("")
                    ForEach(Examiner.englishVoices, id: \.identifier) { v in
                        Text("\(v.name) · \(v.language)\(v.quality == .premium ? " · 高品质" : v.quality == .enhanced ? " · 增强" : "")").tag(v.identifier)
                    }
                }
                HStack {
                    Text("语速")
                    Slider(value: $settings.examinerRate, in: 0.38...0.56)
                    Button("试听") {
                        examiner.voiceIdentifier = settings.examinerVoice.isEmpty ? nil : settings.examinerVoice
                        examiner.rate = Float(settings.examinerRate)
                        Task { await examiner.say("Now, in this first part of the test, I'd like to ask you some questions about yourself. Do you work or are you a student?") }
                    }
                }
                Text("可在「系统设置 › 辅助功能 › 朗读内容 › 系统声音」中下载更自然的英语声音（如 Serena、Daniel 高品质版）。").font(.caption).foregroundStyle(.secondary)
            }
            Section("作答") {
                Toggle("显示考官问题的文字（真实考试中没有）", isOn: $settings.speakingShowText)
                Picker("说完后自动进入下一题", selection: $settings.speakingAutoEnd) {
                    Text("关闭（只用「回答完毕」按钮）").tag(0.0)
                    ForEach([2.0, 3, 4, 5, 6, 8], id: \.self) { Text("静音 \(Int($0)) 秒后").tag($0) }
                }
                Text("Part 2 的独白只在讲满 2 分钟或点「回答完毕」时结束，不会因为停顿自动结束。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
