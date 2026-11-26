# PassCard（凭证卡）

截图 → 多模态模型识别 → 锁屏 / 灵动岛卡片。iOS 客户端。

## 这个仓库必须整体作为 git 仓库根目录

GitHub 只读取**仓库根目录**下的 `.github/workflows/`。如果你把上一级目录
（同时包含 `floato-backend`）作为仓库根推上去，CI 不会运行，`xcodegen generate`
也会在错误的目录里执行。

```bash
cd floato-ios
git init && git add -A && git commit -m "PassCard iOS client"
git remote add origin <你的仓库>
git push -u origin main
```

后端 `floato-backend` 放另一个仓库，或者放同一个仓库但把 workflow 移到根目录并
加上 `working-directory: floato-ios`。

**仓库建议设为 public**：macOS 分钟数按 10 倍计费，私有仓库免费额度 2000 分钟/月
只够跑大约两次 CI。公开仓库的 macOS 分钟数不限。仓库里没有密钥——模型密钥只存在
后端的环境变量里。

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
```

## 跑起来

1. 在电脑上启动后端（需要 `ARK_API_KEY` 和 `ARK_MODEL` 环境变量）：
   ```bash
   cd ../floato-backend
   python server.py        # 监听 127.0.0.1:8787
   ```
   `server.py` 默认只绑 `127.0.0.1`，手机连不上。改成 `0.0.0.0` 或在
   `ThreadingHTTPServer(("0.0.0.0", port), Handler)` 处修改，然后放行 Windows
   防火墙的入站端口。

2. 查这台电脑的局域网 IP：`ipconfig` → IPv4 地址，例如 `192.168.1.20`。

3. 真机装 App（需要 Apple Developer 账号签名），手机和电脑连同一个 Wi-Fi，
   App → 设置 → 后端地址填 `http://192.168.1.20:8787` → 点「测试连接」。
   显示模型名就是通了。

4. 点右上角加号选截图。**灵动岛只能在真机上验证，模拟器不渲染灵动岛**；锁屏
   Live Activity 在模拟器上可以看到。

## 上架前必须改

- `project.yml` 里的 `com.example.*` Bundle ID 换成自己的。
- 删掉 `NSAllowsArbitraryLoads`（局域网明文 HTTP 的临时开关，App Store 审核会问）。
- 补 App 图标（目前没有 asset catalog，装到手机上是空白图标）。
- 后端要有公网 HTTPS 地址，不能是局域网 IP。
- 中国区上架需要 ICP 备案；涉及生成式 AI 可能还有额外备案要求。

## 契约

Swift 侧的类型标识符和字段名必须和 `../floato-backend/passes.py` 的 `SPEC` 一致。
`Tests/PassCardTests.swift` 里的 JSON 字面量就是后端 `pipeline._finish` 的真实
输出形状，改任何一边都要同时改另一边。
