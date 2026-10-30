# 雅思模考

**一个原生 macOS 雅思模拟考试客户端。** 内置剑桥雅思 4–18 全部 60 套学术类真题（听力 / 阅读 / 写作），界面参照雅思官方机考，带真实倒计时和时间提醒；交卷后可以接入你自己的 Claude 或 OpenAI API Key，让 AI 逐题解析错题、给作文打分并提出修改建议。

[⬇️ 下载最新版 DMG](../../releases/latest) · macOS 14 及以上 · Apple Silicon（M 系列芯片）

![首页](docs/screenshots/home.png)

---

## 目录

- [功能一览](#功能一览)
- [界面预览](#界面预览)
- [安装](#安装)
- [使用指南](#使用指南)
- [AI 解析与写作评分（BYOK）](#ai-解析与写作评分byok)
- [题库说明](#题库说明)
- [从源码构建](#从源码构建)
- [题库是怎么做出来的](#题库是怎么做出来的)
- [仓库结构](#仓库结构)
- [隐私](#隐私)
- [版权声明](#版权声明)

---

## 功能一览

### 真题题库
- **剑桥雅思 4–18，共 60 套学术类真题**（剑 12 为 Test 5–8），每套包含完整的听力、阅读、写作三个科目。
- 听力配**官方录音**和**完整听力原文**（带原书页边的题号定位标记）。
- 写作附原书的**考官范文 / 考生范文**、分数和考官评语（共 120 篇）。
- 覆盖全部常见题型：笔记 / 表格 / 流程图 / 摘要 / 句子填空，单选、多选，TRUE/FALSE/NOT GIVEN、YES/NO/NOT GIVEN，段落标题匹配、段落信息匹配、人物 / 特征分类匹配，地图 / 平面图 / 示意图标注等。
- 支持导入自定义题目（同一份 JSON 格式），也可以为缺失或想替换的听力单独导入音频。

### 模拟考试
- **三种模式**
  - **全真模考**：听力 → 阅读 → 写作连考，严格计时，中途不能暂停。
  - **单科模考**：只考听力、阅读或写作中的一科。
  - **专项练习**：单个 Part / Passage / Task 限时练习，可以暂停。
- **真实计时**
  - 阅读 60 分钟、写作 60 分钟（建议 Task 1 用 20 分钟、Task 2 用 40 分钟）。
  - 听力以录音为准：录音连续播放、不能回放，播完后有检查时间，可在设置中选机考 2 分钟或纸笔考 10 分钟。
- **时间提醒**：剩余 10 / 5 / 1 分钟时在界面顶部弹出提醒，App 在后台时也会发系统通知，可以开启提示音。
- **中途退出可恢复**：自动保存进度，下次从首页继续。

### 机考同款界面
- 顶栏显示 "35 minutes left"，最后两分钟按秒倒计时；可点 **Hide** 隐藏计时（提醒照常弹出）。
- 灰色说明框（"Part 1 · Read the text and answer questions 1–13."）。
- 阅读左右分栏：左边文章、右边题目，分栏宽度可以拖动。
- 填空框里显示题号，按回车跳到下一题。
- 底部题号导航：已答题号带下划线；勾选 **Review** 的题号显示为圆框，方便回头检查。
- 右下角深色 ← → 切题、✓ 交卷。
- ☰ 菜单里可以调**对比度**（黑底白字 / 黑底黄字）和**字号**（Standard / Large / Extra large），⌘+ / ⌘- 可以微调字号。
- 阅读文章可以**选中高亮**（右键 → 高亮 / 清除）。
- 标题匹配题可以把标题**直接拖到对应段落上方**。

### 复盘与记录
- 交卷立即判分：逐题对错、你的答案对照正确答案、按题型统计正确率，并按官方换算表给出 **Band 分**。
- **对照原文复盘**：按原试卷版式查看自己的答案和标准答案；听力可以边听录音边看原文，原文里的题号定位会按对错着色。
- **错题本**：汇总所有做错的题，可按科目、题型筛选。
- **写作记录**：保存每篇作文和 AI 评分。
- **首页统计**：分数趋势图、薄弱题型、累计练习时长。
- 练习记录可以导出备份，也可以从备份导入。

### AI 解析与评分（可选）
- 支持 **Claude（Anthropic）** 和 **OpenAI**，用你自己的 API Key，也支持兼容的自定义 Base URL。
- **错题解析**：指出原文出处（复盘时在文章或听力原文中高亮显示）、题干和原文之间的同义替换，说明正确答案为什么对、你的答案为什么错，并给出一条针对该题型的做题技巧。
- **写作评分**：按官方四项评分标准（Task Achievement / Response、Coherence & Cohesion、Lexical Resource、Grammatical Range & Accuracy）给出分项分和总分，列出优点和主要问题，并逐句给出修改建议。Task 1 会把图表一起发给模型。

---

## 界面预览

| 题库 | 阅读（左右分栏） |
|---|---|
| ![题库](docs/screenshots/library.png) | ![阅读](docs/screenshots/reading.png) |

| 听力（录音连播） | 写作 |
|---|---|
| ![听力](docs/screenshots/listening.png) | ![写作](docs/screenshots/writing.png) |

| 黑底黄字对比度 | 交卷结果 |
|---|---|
| ![对比度](docs/screenshots/contrast.png) | ![结果](docs/screenshots/result.png) |

| 对照原文复盘 |
|---|
| ![复盘](docs/screenshots/review.png) |

---

## 安装

1. 到 [Releases](../../releases/latest) 下载 `雅思模考-x.y.z.dmg`（约 1.4 GB，题库和全部听力音频已内置）。
2. 双击打开 DMG，把「雅思模考」拖进「Applications（应用程序）」。
3. **第一次打开**：App 是本地自签名的，没有经过苹果公证，macOS 会提示"无法验证开发者"。
   - 在 Finder 中右键点 App →「打开」→ 再点「打开」；
   - 或者到「系统设置 › 隐私与安全性」，点「仍要打开」。
   
   之后就可以正常打开。

覆盖安装新版本不会丢失练习记录和 API Key。

---

## 使用指南

### 开始一场考试
- 在**首页 › 快速开始**直接开始下一套没做过的题，或者随机练一篇阅读。
- 也可以在**题库**里选书和套题，进入详情页后选择：
  - **开始全真模考**：听力、阅读、写作连考；
  - **听力模考 / 阅读模考 / 写作模考**：单科；
  - 某个 Part / Passage / Task 后面的**练习**：专项练习。
- 每个科目开始前有一页考生须知，点**开始**后才计时。

### 作答
| 操作 | 方式 |
|---|---|
| 上一题 / 下一题 | 右下角 ← →，或 ⌘← / ⌘→ |
| 填空后跳到下一题 | 回车 |
| 标记稍后检查 | 底部左侧勾选 **Review** |
| 高亮文章 | 选中文字 → 右键 → 高亮 |
| 标题匹配 | 把标题拖到段落上方，或用下拉框选择 |
| 调字号 | ☰ › Text size，或 ⌘+ / ⌘- / ⌘0 |
| 调对比度 | ☰ › Contrast |
| 隐藏计时 | 顶栏 **Hide** |
| 交卷 | 右下角 ✓ |
| 退出（保存进度） | ☰ › 退出考试 |

### 判分规则
- 不区分大小写，忽略首尾标点；£ $ € 这类题目里已经印出的单位可写可不写。
- 1,500 和 1500 视为相同，9:30 和 9.30 视为相同。
- 答案键里的可选词，比如 `(the) harbour / harbor`，会展开成所有可接受的写法。
- 标注 **IN EITHER ORDER** 的两题，答案顺序不限。
- 多选题按每个正确选项计分。
- 不检查字数限制，请自己注意题目要求，比如 "NO MORE THAN TWO WORDS"。
- 原始分按剑桥官方学术类换算表转成 Band 分。

---

## AI 解析与写作评分（BYOK）

1. 打开**设置 › AI**，选择服务商（Claude 或 OpenAI），粘贴 API Key，点**保存 Key**，再点**测试连接**。
2. 交卷后在结果页点 **AI 解析错题**，可以解析某个 Part / Passage，也可以一次解析全部；写作页点 **AI 评分**。
3. 可以调整的选项：

| 设置 | 默认值 | 说明 |
|---|---|---|
| 模型（Claude） | `claude-opus-5-5` | 也可以选 Sonnet 5.5 / Haiku 5.5 / Fable 5.1，或者自己填写模型名 |
| 模型（OpenAI） | `gpt-6-astra` | 可选列表中的其他型号，或者自己填写 |
| Base URL | 官方地址 | 可以填 Anthropic / OpenAI 兼容的代理或中转地址 |
| 错题解析推理强度 / 写作评分推理强度 | medium / high | 越高越细致，也越慢、越贵 |
| 解析语言 | 简体中文 | 也可以选 English |

- 请求使用流式输出和 JSON Schema 结构化结果；如果自定义端点不支持某个参数，会自动降级重试。
- Key 只存在本机**钥匙串**里，不会写进配置文件，也不会发到任何第三方服务。
- 费用由你的 API 账户承担。解析一个 Part 的错题大约需要一次请求，写作评分每篇一次请求。

---

## 题库说明

| 书 | 套题 | 来源 | 备注 |
|---|---|---|---|
| 剑 4 | T1–T4 | 原书完整扫描 | |
| 剑 5–8 | T1–T4 | 原书扫描 | 剑 5 只取学术类；部分配图上印有第三方水印，已经去除 |
| 剑 9 | T1–T4 | 第三方重新排版的电子版 | 明显的录入错误已改正，每处改动都记在该套题的 `issues` 里 |
| 剑 10–11 | T1–T4 | 原书扫描 | |
| 剑 12 | T5–T8 | 原书扫描 | 剑 12 的套题编号就是 5–8 |
| 剑 13–18 | T1–T4 | 原书扫描 | |

**已知缺口**
- **剑 15 Test 4**：听力 Part 1、Part 2 的录音缺失，源仓库中没有这两段音频。可以在该套题的详情页用「导入音频…」补上。
- **剑 13 Test 3**：扫描件缺原书第 54–55 页，听力第 1–16 题的题面依据三份网上录入版重建，并和原书答案、听力原文交叉核对过。
- 少数地方原书本身就有印刷错误，比如题目说明写"七段"，实际有八段；这些都按原书照录，并在 `issues` 里注明。

每套题的 `issues` 字段记录了所有不能完全照原书还原的地方，以及每一处人工判断。

---

## 从源码构建

需要 macOS 14+ 和 Xcode 命令行工具（Swift 5.10+）。

```bash
git clone https://github.com/yanboishere/ielts-mock.git
cd ielts-mock/app

swift build                 # 编译
scripts/build_app.sh        # 生成 build/雅思模考.app（自签名）
scripts/build_app.sh --install   # 生成并拷贝到 /Applications
```

### 安装题库

仓库里有全部题目的 JSON 和配图（`data/bank/`），但**没有听力音频和原书页面图**，它们体积太大，只打包在 Release 的 DMG 里。你可以：

- **最简单**：从 Release DMG 里的 `雅思模考.app/Contents/Resources/Bank` 拷出完整题库；
- **自己生成**：准备好原书 PDF 和音频，按下一节的流程跑一遍，然后用
  ```bash
  scripts/install_bank.py            # 安装到 ~/Library/Application Support/IELTSMock/Bank
  ```
  `install_bank.py` 会按 `data/build/audiomap.json` 把音频复制进题库，并生成「原书页面」用的缩略图。

App 查找题库的顺序：设置里指定的文件夹 → App 包内的 `Contents/Resources/Bank` → `~/Library/Application Support/IELTSMock/Bank`。

### 打包 DMG

```bash
scripts/make_dmg.sh   # 把题库打进 App，生成 build/雅思模考-<版本>.dmg
```

### 开发调试
- `IELTSMOCK_DEBUG=1` 启动时会开启一个本地调试通道。用 `scripts/debugctl.swift` 可以远程操作 App，例如切换页面、开考、填写答案、交卷，还能截取窗口图，不需要屏幕录制权限。
- `scripts/mock_llm.py` 是一个本地假的 Claude / OpenAI 端点。它按请求里的 JSON Schema 生成结果，可以在不花钱的情况下测试 AI 相关流程。

---

## 题库是怎么做出来的

```
原书 PDF ──渲染+OCR──▶ 逐页文字和坐标 ──结构识别──▶ 页码索引
                                         │
                       抽题（每套一个 AI 代理，看页面图 + OCR）
                                         ▼
                 data/work/BOOK-TN/{listening,reading,writing}.json
                                         │  ielts assemble（合并 + 校验）
                                         ▼
                        data/bank/exams/BOOK-TN.json ──▶ App
```

1. **渲染与 OCR**（`tools/pdfrender.swift`、`tools/pdfocr.swift`）：用 macOS 自带的 PDFKit 和 Vision 把每一页渲染成图片，识别出文字，并保留每一行的坐标。
2. **结构识别**（`tools/py/events.py`、`structure.py`）：找出每套题的听力、阅读、写作页码，以及听力原文、答案页、范文页的位置。音频按书 / 套题 / Part 对应到文件（`audiomap.py`）。
3. **抽题**：每套题交给一个 AI 代理，按 `data/AGENT_BRIEF.md` 和 `data/SCHEMA.md` 工作：
   - 用 `tools/bin/ielts` 查看页面、局部放大重新 OCR、裁剪配图；
   - 照原书逐字录入题目和文章；
   - 答案一律**看答案页图片**逐栏转录。
4. **合并与校验**（`ielts assemble` / `ielts validate`）：检查题号 1–40 是否各出现一次、每个空是否都有答案、选项字母是否对得上、图片是否存在等。
5. **质检**（`tools/qa/`）：
   - `coverage.py`：把原书页面切成重叠的横条，放大后**重新做一次 OCR**，逐行确认每一句都在题库 JSON 里，用来找出漏行；
   - `confirm_flags.py`：对标出的行做模糊匹配，排除重新识别时认错字造成的误报，剩下的再人工看原图确认；
   - `dewatermark.swift`：去掉黑白配图上的彩色第三方水印。

`data/qa/` 里是每本书的质检报告，`data/work/` 里是每套题的分模块工作文件。

---

## 仓库结构

```
app/                     macOS App（SwiftUI，Swift Package）
  Sources/IELTSMock/
    App/                 入口、全局状态、调试通道
    Model/               题目数据模型、判分与 Band 换算、练习记录
    Bank/ Store/         题库加载、设置、钥匙串、历史记录
    Exam/                考试会话（计时、提醒、听力连播、自动保存）
    AI/                  Claude / OpenAI 客户端、提示词、结构化输出
    Views/               首页 / 题库 / 考试 / 复盘 / 错题本 / 写作记录 / 设置
  scripts/               build_app.sh · make_dmg.sh · install_bank.py · debugctl · mock_llm.py
tools/                   抽题和质检工具（Swift + Python）
  bin/ielts              抽题命令行工具：pagetext / pageview / ocrzoom / figcrop / assemble / validate …
  qa/                    coverage / confirm_flags / dewatermark
  build.sh               编译 Swift 工具
data/
  SCHEMA.md              题库 JSON 格式说明
  AGENT_BRIEF.md         抽题规范（给代理的工作说明）
  books.json             每本书的来源 PDF 和套题编号
  bank/exams/            60 套题的 JSON
  bank/images/           题目用到的地图、图表和写作 Task 1 图
  work/                  每套题的分模块工作文件
  build/audiomap.json    听力音频对应表
  qa/                    逐行完整性检查报告
docs/screenshots/        README 截图
```

抽题工具默认在 `~/ielts-tools` 和 `~/ielts-data` 下工作，用软链接即可：

```bash
ln -s "$PWD/tools" ~/ielts-tools && ln -s "$PWD/data" ~/ielts-data && tools/build.sh
```

---

## 隐私

- 所有练习记录、作文和设置都只保存在本机：`~/Library/Application Support/IELTSMock` 和钥匙串。
- App 只在你主动使用 AI 功能时联网，直接请求你配置的 Claude / OpenAI 端点。请求内容包括相关文章或听力原文、题目、你的答案或作文。
- 没有任何统计、遥测或第三方服务。

---

## 版权声明

本项目的**源代码和工具**由作者编写。

**题库内容**（题目、文章、听力原文、录音、范文和图表）来自《剑桥雅思真题》（Cambridge IELTS）系列，版权归 **Cambridge University Press & Assessment** 所有。本仓库整理这些内容**仅供个人学习和交流使用，请勿用于任何商业用途**。如果你是版权方并希望移除相关内容，请提交 Issue 联系，收到后会尽快处理。请支持正版图书。

IELTS 是 British Council、IDP: IELTS Australia 和 Cambridge University Press & Assessment 的注册商标，本项目与上述机构没有任何关联。
