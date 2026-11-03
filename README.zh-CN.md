<div align="center">
    <img src="Ice/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200>
    <h1>Ice</h1>
</div>

<p align="center">
    <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

Ice 是一款开源的 macOS 菜单栏管理工具。本仓库是
[Alarak-Alex/Ice](https://github.com/Alarak-Alex/Ice)，基于
[jordanbaird/Ice](https://github.com/jordanbaird/Ice) 开发，改进了设置界面，
加入英文和简体中文切换，并为 macOS 27 提供独立的菜单栏布局编辑器。

![横幅](https://github.com/user-attachments/assets/4423085c-4e4b-4f3d-ad0f-90a217c03470)

[![开发分支](https://img.shields.io/badge/branch-macos--27--build-brightgreen?style=flat-square)](https://github.com/Alarak-Alex/Ice/tree/macos-27-build)
![平台](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![系统要求](https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=flat-square)
[![赞助原作者](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=flat-square)](https://github.com/sponsors/jordanbaird)
[![原版官网](https://img.shields.io/badge/Website-015FBA?style=flat-square)](https://icemenubar.app)
[![许可证](https://img.shields.io/github/license/Alarak-Alex/Ice?style=flat-square)](LICENSE)

> [!NOTE]
> 本分支仍在开发，当前开发分支为 `macos-27-build`。macOS 27 的布局和可见性功能
> 属于实验阶段，验证范围见下文。上游发行包和 Homebrew 安装的是原版 Ice，
> 不包含本仓库的改动。

## 本分支的改动

英文版与中文版 README 对应同一开发阶段，同步更新于 **2026 年 11 月 3 日**。

- **设置与导航：** 使用原生 AppKit 搜索框和侧边栏，分离点击区域，支持键盘导航、
  前进与后退，采用统一工具栏、系统语义颜色和紧凑的分组设置。
- **语言切换：** 在“通用”中选择跟随系统、English 或简体中文。切换立即生效，
  并记住选择。
- **macOS 27 布局：** 通过辅助功能发现由 MenuBarAgent 托管的项目，提供三个单行
  分区、配置管理、按显示器自动选择配置，以及为新发现应用设置插入位置的拖动标记。
  编辑器中点击图标只会选中项目，不会打开对应应用的菜单。
- **横向浏览：** 支持触控板横向手势、鼠标滚轮、原生滚动条，以及拖动项目条的空白
  背景来查看超出可视范围的项目。刷新会保留浏览位置；拖动图标用于排序。
- **调色板间隔：** 间隔宽度以 1–200 点保存到配置中，使用稳定标识和显式空白图像
  创建原生状态栏项目，支持修改宽度、移除，以及注册失败时回滚。原生间隔注册和
  实际拖放仍需完成运行时验收。
- **macOS 27 隐藏项目显示：** 空白区域点击已接入临时显示“隐藏项目”的逻辑，
  不包含“始终隐藏”。图像重新捕捉和临时显示分别使用恢复日志，在结束或会话中断后
  恢复原可见性。真实菜单栏空白点击仍需完成运行时验收。
- **原生偏好设置：** 排序和可见性写入包含旧状态校验、并发变更检测、备份、
  文件访问选择器和撤销。
- **图像与间距：** 捕捉菜单栏图标并裁剪，无法使用时回退到 App 图标；提供重新捕捉
  控件，以及默认、小、极小、无间距四种设置。退出登录后重新登录可让所有状态栏
  项目应用新间距。
- **性能与生命周期：** 跟踪模式监听器观察事件队列，不再取出并重新投递队列事件；
  对待处理事件去重；订阅取消时释放订阅者；退出的应用图像从常驻内存缓存中移除，
  磁盘缓存继续保留。
- **构建与启动：** 增加登录启动错误反馈、CompactSlider 本地依赖兼容修复，
  以及带签名校验的本地安装脚本。

实现说明和可复现的回归检查命令见 [FORK.md](FORK.md)。

## 兼容性与验证范围

| 项目 | 当前状态 |
| --- | --- |
| 最低部署版本 | macOS 14 |
| macOS 14–26 | 保留原有布局与隐藏引擎；尚未在运行中的 macOS 26 上验证功能和外观 |
| macOS 27 | 使用独立布局编辑器和原生排序、可见性路径；已在本机验证签名 Release 构建与安装 |
| 本机工具链 | Xcode 27.2 / macOS SDK 27.2 |
| 专项检查 | 布局和语言持久化、原生偏好事务、配置及撤销、仅显示隐藏项目及恢复、间隔内容与生命周期、单行视图和横向输入、图像处理、导航、间距、事件监听取消 |
| 运行时检查 | 已验证即时切换语言、侧边栏选择、偏好设置恢复，以及溢出项目条可以到达最右端；限制见下文 |

原有 Ice 栏尚未移植到 macOS 27 的 MenuBarAgent。与 Bartender 的像素级一致性、
前台真实拖放与拖动浏览、原生间隔位置、真实菜单栏空白点击、多显示器行为，
以及 macOS 26 运行时一致性仍未完成验证。

性能采样中已不再出现此前的跟踪循环热点。本机泄漏快照仍有尚未通过调用栈明确归属
的分配记录；这一阶段**不能证明零泄漏、长期内存稳定，或严格对照条件下的整体
CPU 改善**。

## 安装

### 构建本分支

```sh
git clone --branch macos-27-build https://github.com/Alarak-Alex/Ice.git
cd Ice
open Ice.xcodeproj
```

在 Xcode 中选择 Ice scheme，配置自己的签名团队后构建。使用本地 Release 安装
脚本时，请提供本机已有的签名证书名称和团队 ID：

```sh
SIGN_IDENTITY="Apple Development: Your Name (CERTIFICATE_ID)" \
SIGN_TEAM="YOUR_TEAM_ID" \
./Scripts/install-local.sh
```

脚本安装到 `/Applications/Ice.app`，验证签名，并关闭 Sparkle 自动更新，
防止被上游构建覆盖。连续构建时保持相同的 Bundle ID 和签名身份，
以保留已有权限授权。

请在系统设置中允许“辅助功能”权限以管理菜单栏。“屏幕录制”用于捕捉项目图像。
无法读取原生偏好文件时，布局编辑器会提供文件访问选择器。

### 安装上游原版

从[上游发行页](https://github.com/jordanbaird/Ice/releases/latest)下载 `Ice.zip`，
解压后移到“应用程序”，或者通过 Homebrew 安装上游 cask：

```sh
brew install --cask jordanbaird-ice
```

以上两种发行方式不包含前文列出的本分支改动。

## 原有功能与路线图

下表清单描述继承的功能。macOS 27 请以兼容性表为准，并非所有旧版功能都已完成
移植。本分支新增的实验性配置与间隔功能已在上文单独说明。

### 菜单栏项目管理

- [x] 隐藏菜单栏项目
- [x] “始终隐藏”分区
- [x] 悬停于菜单栏时显示隐藏项目
- [x] 点击菜单栏空白处显示隐藏项目
- [x] 在菜单栏滚动或轻扫时显示隐藏项目
- [x] 自动重新隐藏菜单栏项目
- [x] 应用菜单与显示的项目重叠时隐藏应用菜单
- [x] 拖放排列菜单栏项目
- [x] 在独立栏中显示隐藏项目，例如用于有刘海的 MacBook
- [x] 搜索菜单栏项目
- [x] 菜单栏项目间距（测试阶段）
- [ ] 菜单栏项目分组
- [ ] 满足触发条件时显示菜单栏项目

### 菜单栏外观

- [x] 菜单栏着色，支持纯色和渐变
- [x] 菜单栏阴影
- [x] 菜单栏边框
- [x] 自定义菜单栏形状，支持圆角与分段
- [ ] 移除菜单栏背景
- [ ] 屏幕圆角
- [ ] 分别设置浅色与深色模式

### 快捷键

- [x] 切换各菜单栏分区
- [x] 显示搜索面板
- [x] 启用或停用 Ice 栏
- [x] 显示或隐藏分区分隔图标
- [x] 切换应用菜单
- [ ] 启用或停用自动重新隐藏
- [ ] 临时显示单个菜单栏项目

### 其他

- [x] 登录时启动
- [x] 自动更新
- [ ] 菜单栏小组件

## 为什么只支持 macOS 14 及以上？

Ice 使用了从 macOS 14 开始提供的一些系统 API，因此没有支持更早系统的计划。

## 图库

以下截图展示的是上游原版界面。

#### 在菜单栏下方显示隐藏项目

![Ice 栏](https://github.com/user-attachments/assets/f1429589-6186-4e1b-8aef-592219d49b9b)

#### 拖放排列菜单栏项目

![菜单栏布局](https://github.com/user-attachments/assets/095442ba-f2d0-4bb4-9632-91e26ef8d45b)

#### 自定义菜单栏外观

![菜单栏外观](https://github.com/user-attachments/assets/8c22c185-c3d2-49bb-971e-e1fc17df04b3)

#### 搜索菜单栏项目

![菜单栏项目搜索](https://github.com/user-attachments/assets/d1a7df3a-4989-4077-a0b1-8e7d5a1ba5b8)

#### 自定义菜单栏项目间距

![菜单栏项目间距](https://github.com/user-attachments/assets/b196aa7e-184a-4d4c-b040-502f4aae40a6)

## 许可证

Ice 使用 [GPL-3.0 许可证](LICENSE)。

原版 Ice 由 Jordan Baird 及其贡献者开发。本分支的 macOS 27 发现和图像处理工作
还参考了 [Icey](https://github.com/leonardovida/icey)，版本
`0cb4b09cd401326adb19a15cdb4040235b70c924`（GPL-3.0）。
Bartender 用作行为与视觉参考，本仓库不包含其代码或素材。

可以通过 [GitHub Sponsors](https://github.com/sponsors/jordanbaird) 或
[Buy Me a Coffee](https://www.buymeacoffee.com/jordanbaird) 支持原作者。
