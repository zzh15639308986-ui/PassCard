# PassCard（凭证卡）

截图 → 多模态模型识别 → 锁屏 / 灵动岛卡片。仓库根目录是 iOS 客户端，识别后端在
`backend/`（纯 Python，只用标准库，没有第三方依赖）。

## 仓库结构

```
project.yml  Sources/  Widget/  Tests/   iOS 客户端（工程由 XcodeGen 生成）
.github/workflows/ci.yml                 三个 job：macOS 编译测试、ubuntu 后端测试、
                                         macOS 产出可侧载的未签名 .ipa
backend/                                 识别后端 + 合成截图评测
```

GitHub 只读取**仓库根目录**下的 `.github/workflows/`，所以 workflow 留在根目录：
iOS job 直接用仓库根，后端 job 用 `defaults.run.working-directory: backend`。
`project.yml` 的 sources 是显式列出的（`Sources`、`Widget`、`Tests`），XcodeGen
不会把 `backend/` 扫进工程。

**仓库必须保持 public**：macOS 分钟数按 10 倍计费，私有仓库免费额度 2000 分钟/月
只够跑大约两次 CI；公开仓库的 macOS 分钟数不限。

仓库里没有密钥，也永远不要有：模型密钥放在仓库外的 `ark.env`（`measure.py
--env-file` 读它，`server.py` 读环境变量）。真截图的评测结果
（`backend/synthetic/report-real.json`、`truth-real.json`、`labels-real.json`）
含乘车人姓名、手机尾号、订单号，已 gitignore。CI 里还有一步会检查这三个文件、
任何 `.env`、以及密钥形状的字符串有没有被跟踪，防止公开仓库漏出去。

## 本地无法编译

工程在 Windows 上编写，没有 `.xcodeproj`（由 XcodeGen 从 `project.yml` 生成，已
gitignore）。**GitHub Actions 的 macOS runner 是第一个编译器**。推上去看 Actions
结果。

## 目录

```
project.yml                        XcodeGen 工程定义（3 个 target）
Sources/Shared/                    App 和 Widget Extension 共同编译
  JSONValue.swift                  后端异构 fields 的解码 + 日期解析
  PassType.swift                   9 种凭证类型，rawValue 对齐后端 SPEC
  Pass.swift                       持久化模型
  PassActivityAttributes.swift     ActivityKit 属性与 ContentState
  PassPresentation.swift           Pass → 展示字段的唯一映射
Sources/Networking/                RecognitionClient（原始字节 POST）、图片压缩
Sources/Models/                    PassStore（JSON 文件存储）、LiveActivityController
Sources/App/                       @main、AppSettings
Sources/Views/                     列表、行、设置
Widget/                            Live Activity 的锁屏与灵动岛 UI（@main 扩展入口）
Tests/                             与后端契约的单元测试
backend/ark.py                     Ark chat/completions 客户端：重试、用量统计、thinking 开关
backend/passes.py                  SPEC：9 种凭证类型和字段，Swift 侧必须对齐
backend/prompts.py                 分类与逐类型抽取的提示词
backend/pipeline.py                两级路由（分类 → 抽取 → 可选修复）+ SHA256 图片缓存
backend/server.py                  本地 HTTP 服务，默认只绑 127.0.0.1:8787
backend/measure.py                 批量评测：准确率 / 延迟 / token 成本
backend/test_pipeline.py           30 个离线用例（假 client，不联网，不需要密钥）
backend/synthetic/                 合成截图、真值、渲染脚本、字段级评分器、评测报告
```

## 后端怎么测

```bash
cd backend
py test_pipeline.py
```

30 个用例全走假 client，不联网、不需要密钥，退出码 0 才算过。CI 的
`backend-tests` job 就是跑这个。

要花 token 的真实评测（需要 `ARK_API_KEY` 和 `ARK_MODEL`）：

```bash
cd backend
py measure.py synthetic/*.png --labels synthetic/labels.json \
  --out synthetic/report.json --env-file ~/ark.env --no-think
py synthetic/grade_fields.py synthetic/report.json
```

通配符只在 git-bash 里展开；PowerShell 得写全路径或先
`(ls synthetic\*.png).FullName`。

已提交的 `synthetic/report-lite-nothink.json` 和 `report-lite.json` 是同一批合成
截图在 `doubao-seed-2-1-lite-260915` 上的两次原始运行：

| | 类型识别 | 平均延迟 | p95 | 每张 token | 每张成本 |
|---|---|---|---|---|---|
| 关推理（`--no-think`） | 8/8 | 2.58 s | 3.07 s | 2841 | 0.0025 元 |
| 开推理（模型默认） | 8/8 | 27.4 s | 85.0 s | 4821 | 0.0078 元 |

价格按火山方舟官方文档：seed-2.1-lite 输入 0.8 元/百万 token、输出 2.7 元/百万
token。Seed 2.1 默认开推理，而且把推理算进输出 token 计费，所以 `server.py`
默认关推理。

另外两张真截图（未入库，因为含个人信息）结果一致：类型 2/2、字段 11/11、
3.2–3.9 秒、每张 0.0026 元。`grade_fields.py` 的严格字段口径在关推理那次是
48/52，4 处差异全是写法（`浦东机场` vs `上海浦东`、`05` vs `05车`），人读是
52/52。

## 跑起来

1. 在电脑上启动后端（需要 `ARK_API_KEY` 和 `ARK_MODEL` 环境变量）：
   ```bash
   cd backend
   py server.py --host 0.0.0.0
   ```
   不加 `--host` 就只绑 `127.0.0.1`，手机连不上。加了之后启动横幅会直接打印手机
   该填的地址（例如 `http://192.168.160.41:8787`），以及 Windows 防火墙的放行
   命令——**那条 `netsh` 要在管理员权限的终端里跑一次**，不然手机连不上。
   这个端口没有任何鉴权，每个请求都在花你的 Ark 额度，用完就 Ctrl+C 关掉。

2. 手机和电脑连同一个 Wi-Fi，App → 设置 → 后端地址填横幅打印的那个地址 →
   点「测试连接」。显示模型名就是通了。

3. 点右上角加号选截图。**灵动岛只能在真机上验证，模拟器不渲染灵动岛**；锁屏
   Live Activity 在模拟器上可以看到。

## 装到 iPhone（没有 Mac）

CI 的 `sideload-ipa` job 产出一个**未签名**的 `.ipa`，用 Windows 上的侧载工具配
你自己的免费 Apple ID 签名安装。

1. 仓库 Actions → 最近一次成功的运行 → 页面最下方 Artifacts → 下载
   `PassCard-unsigned-ipa`（保留 30 天），解压得到 `PassCard-unsigned.ipa`。
2. 装 Sideloadly 或 AltStore。**这两个都是第三方工具，我不会替你下载或运行**，
   你自己从官网装。
3. iPhone 用数据线连电脑，在 Sideloadly 里选这个 `.ipa`，Apple ID 填你自己的
   （免费账号就行，不需要 99 美元的开发者账号），点 Start。
4. 手机上第一次打开前，去「设置 → 通用 → VPN 与设备管理」信任你自己的
   开发者证书。

已知限制：

- 免费 Apple ID 签的名 **7 天过期**，到期 App 打不开，重跑一次侧载即可。
- 免费账号同时最多装 3 个侧载 App。
- 这个 App 带 Widget Extension（灵动岛和锁屏卡片就是它画的），**免费个人签名
  能不能带上扩展我没有验证过**。如果侧载报错、或者装上了但没有灵动岛，说一声，
  我给 CI 加一个不含扩展的变体，先把主流程跑通。
- Bundle ID 还是 `com.example.PassCard`，侧载工具一般会让你改成自己的；改了不影响
  功能，但两次安装的 App 不共享数据。

## 上架前必须改

- `project.yml` 里的 `com.example.*` Bundle ID 换成自己的。
- 删掉 `NSAllowsArbitraryLoads`（局域网明文 HTTP 的临时开关，App Store 审核会问）。
- 补 App 图标（目前没有 asset catalog，装到手机上是空白图标）。
- 后端要有公网 HTTPS 地址，不能是局域网 IP。
- 中国区上架需要 ICP 备案；涉及生成式 AI 可能还有额外备案要求。

## 契约

Swift 侧的类型标识符和字段名必须和 `backend/passes.py` 的 `SPEC` 一致。
`Tests/PassCardTests.swift` 里的 JSON 字面量就是后端 `pipeline._finish` 的真实
输出形状，改任何一边都要同时改另一边。CI 的两个 job 分别守这两边，但它们不会
互相检查一致性——改 `SPEC` 的时候记得同时改 Swift。
