# 版本控制方案：Git 管代码，SVN 管美术

> 一句话：**Git 只放文本（代码 / Shader / 场景 / 材质 / 配置），SVN 放二进制资产（贴图 / 模型 / 动画 / 地形数据 / 截图）。**
> 两者共用同一个工程目录，Unity 完全不感知——它只读磁盘。

---

## 1. 为什么这么切

不是按"美术还是程序"分，而是按三条硬指标：

| 指标 | 二进制、无法合并 | 单文件大、改一次存一整份 | 需要加锁独占 |
|---|---|---|---|
| Git | ❌ 每次提交存整个 blob | ❌ 仓库迅速膨胀 | ❌ 没有锁 |
| SVN | ✅ 单文件增量存储 | ✅ 差异压缩 | ✅ `svn:needs-lock` |

满足两条以上 → SVN。文本类（`.cs`、`.shader`、`.unity`、`.mat`、`.prefab`、`.asset`）→ Git，因为它们需要 diff、review、分支合并。

**收益**：GitHub 仓库从 5.79 GB 降到约 **4 MB**，clone 秒级；同时 2.36 GB 美术资产一份不少地留在 SVN，还额外获得了文件锁。

---

## 2. 目录分工表

### SVN 管理（约 2.36 GB）

| 路径 | 体积 | 内容 |
|---|---|---|
| `Assets/TerrainSampleAssets/` | 1942 MB | Unity 地形示例包（114 张 16-bit `.tif`） |
| `Assets/Screenshots/` | 185 MB | 效果 / 调试截图 |
| `Assets/Characters/` | 38 MB | 角色贴图（`T_actor_*.png`） |
| `Assets/Textures/` | 33 MB | Ground / Skybox / Vepley 贴图集 |
| `Assets/Grass/Data/` | 23 MB | 烘焙地形数据（`GrassField.bytes`、`RoadMask.asset`） |
| `Assets/Models/` | 19 MB | `Lizhiyan.fbx`、Mixamo 模型 |
| `Assets/SkyCheck/` | 6 MB | 天空盒分阶段验证图 |
| `Assets/Animations/` | 3.7 MB | `*.fbx` 动作 + `.anim` + `.controller` |
| `Assets/Art/` | 0.2 MB | Water 相关美术资源 |
| `Screenshots/` | 107 MB | 顶层开发过程截图（Unity 不引用） |

### Git 管理（约 4 MB）

| 路径 | 内容 |
|---|---|
| `Assets/Codes/` | 游戏逻辑 C# |
| `Assets/Shaders/`、`Assets/Shaders/Zhanshuang/` | NPR / 卡通着色器 |
| `Assets/Grass/Scripts/`、`Editor/`、`Shaders/` | 草地工具链（GrassBaker、GrassScatterTool…） |
| `Assets/Scenes/` | 4 个场景 + 烘焙光照 |
| `Assets/Materials/` | 材质（YAML 文本，可合并） |
| `Assets/Settings/`、`Assets/RenderFeatures/` | URP 配置、Renderer Feature |
| `ProjectSettings/`、`Packages/` | 工程与依赖版本 |
| `.gitignore`、`.gitattributes`、`Tools/`、`VERSION_CONTROL.md` | 工程配置 |

**`Assets/Grass` 为什么只切了 `Data/`**：这个目录里 `GrassBaker.cs`、`GrassScatterTool.cs`、`Grass.shader` 加起来是几十 KB 的真代码，走 SVN 就丢掉了 code review 和分支合并能力；而 `Data/` 里是 14 MB 的 `GrassField.bytes` 和 8 MB 的 `RoadMask.asset`，纯烘焙二进制。切在 `Data/` 这一层，两边都拿到自己擅长的东西。

---

## 3. 首次配置

### 3.1 装 SVN 客户端

**TortoiseSVN**（Windows 首选）：安装时**务必勾选 "command line client tools"**，否则脚本找不到 `svn.exe`。

```powershell
svn --version --quiet
```

### 3.2 准备 SVN 仓库

| 方式 | 地址形如 | 说明 |
|---|---|---|
| 本机试验 | `file:///F:/svn/urp-art` | 先跑通流程，以后再迁移 |
| 自建服务器 | `https://svn.example.com/svn/urp-art` | VisualSVN Server，10 分钟装好 |
| 托管服务 | `svn://xxx.svnprovider.com/urp-art` | 阿里云 / 腾讯云 / RiouxSVN 等 |

本机试验建库：

```powershell
svnadmin create F:\svn\urp-art
```

### 3.3 跑配置脚本

```powershell
# 首次导入（建库目录 → checkout → add → 加锁属性 → commit）
.\Tools\Setup-SvnArt.ps1 -RepoUrl https://svn.example.com/svn/urp-art -Import

# 新机器 / 已有仓库，只拉取
.\Tools\Setup-SvnArt.ps1 -RepoUrl https://svn.example.com/svn/urp-art

# 日常更新全部美术目录
.\Tools\Setup-SvnArt.ps1 -Update
```

### ⚠️ 为什么每个美术目录一个独立工作副本

这是本方案最容易踩的坑，必须理解：

如果只建**一个**工作副本、根设在工程根或 `Assets/`，会出现两个问题：

1. `svn status` 会把 Git 管的 1200 多个文件全部报成 `?`（未跟踪），噪音淹没真正要看的信息；
2. `svn add --parents` 会把 `Assets`、`Assets/Grass` 也变成 SVN 版本化目录——两套系统开始互相污染，某天误执行 `svn add Assets` 就把整个工程（含 `Library`）灌进 SVN。

所以脚本采取**每个美术目录一个独立工作副本**（`.svn` 就在该目录内部）：

```
URP_Projects/
├── .git/                        ← Git
├── Assets/
│   ├── Codes/                   ← Git
│   ├── Grass/
│   │   ├── Data/                ← SVN 工作副本（内含 .svn）
│   │   ├── Data.meta            ← Git
│   │   ├── Scripts/             ← Git
│   │   └── ...
│   ├── Textures/                ← SVN 工作副本（内含 .svn）
│   └── ...
└── Screenshots/                 ← SVN 工作副本（内含 .svn）
```

代价是 `svn update` 要遍历多个目录（脚本的 `-Update` 已封装），换来的是：**任何一次 `svn status` 都只显示真正属于 SVN 的东西**，两套系统边界清晰。

SVN 仓库里的路径与工程目录一一对应：

```
trunk/Assets/TerrainSampleAssets/
trunk/Assets/Screenshots/
trunk/Assets/Characters/
...
trunk/Assets/Grass/Data/
trunk/Screenshots/
```

### 3.4 让新建文件自动加锁（建议）

编辑 `%APPDATA%\Subversion\config`，`[auto-props]` 段加入：

```ini
[auto-props]
enable-auto-props = yes
*.psd = svn:needs-lock=yes
*.tif = svn:needs-lock=yes
*.tiff = svn:needs-lock=yes
*.exr = svn:needs-lock=yes
*.fbx = svn:needs-lock=yes
*.blend = svn:needs-lock=yes
*.max = svn:needs-lock=yes
*.ma = svn:needs-lock=yes
*.mb = svn:needs-lock=yes
*.wav = svn:needs-lock=yes
```

这样以后新增的源文件自动带锁属性，不用重跑脚本。

---

## 4. 日常流程

### 改代码（最常见）

```powershell
git add .
git commit -m "feat: 草地轨迹衰减"
git push
```

### 改美术资产

```powershell
.\Tools\Setup-SvnArt.ps1 -Update        # 先同步别人的改动

svn lock Assets/Textures/Vepley/T_actor_lizhiyan_cloth_02_D.png
# ...编辑...
svn commit -m "art: 立绘衣服贴图重绘" Assets/Textures
# commit 默认释放锁；若用了 --no-unlock 则 svn unlock <file>
```

### 两边都改了（换材质 / 调 prefab 引用）

**分两次提交，先资产后代码**，并在 message 里互相引用：

```powershell
svn commit -m "art: 新增裙摆贴图 T_skirt_01" Assets/Textures
git commit -m "feat: 角色材质切换新裙摆贴图 (ref svn r128)"
```

反过来的话，别人 `git pull` 后引用了一个还不存在的贴图，Unity 立刻报 missing reference。

### 命令对照

| 操作 | Git | SVN |
|---|---|---|
| 拉取 | `git pull` | `svn update` |
| 状态 | `git status` / `git diff` | `svn status` / `svn diff` |
| 提交 | `git commit` + `git push` | `svn commit`（一步到服务器） |
| 撤销本地改动 | `git checkout -- <file>` | `svn revert <file>` |
| 加锁 | 无 | `svn lock <file>` |
| 看文件历史 | `git log -p <file>` | `svn log <file>` |

> SVN 没有本地暂存区，`svn commit` 直接进服务器。所以**提交前一定先 `svn update`**，并检查 `svn status` 里没有陌生的 `?`。

---

## 5. `.meta` 归属规则（最容易出事的地方）

**`.meta` 永远跟着它对应的资产走。**

| 文件 | 归属 | 说明 |
|---|---|---|
| `Assets/Textures/Vepley/x.png` | SVN | 资产本体 |
| `Assets/Textures/Vepley/x.png.meta` | SVN | 同目录，自动跟随 |
| `Assets/Textures.meta` | Git | **目录**的 meta，在 `Assets/` 根下 |
| `Assets/Grass/Data.meta` | Git | **目录**的 meta，在 `Assets/Grass/` 下 |
| `Assets/Grass/Data/GrassField.bytes` | SVN | 目录内容 |

规则天然成立：**目录自身的 `.meta` 留在父目录（Git 管），目录里面的内容归 SVN。** SVN 工作副本的根就是这个目录本身，扫不到外面的 `.meta`。

⚠️ 红线：**绝不能出现"资产在 SVN、它的 `.meta` 在 Git"**。那样只 clone Git 的人会让 Unity 重新生成一个新 GUID 的 `.meta`，全工程引用立刻断裂。

---

## 6. 锁的使用

### 哪些文件被锁了

脚本按扩展名设置 `svn:needs-lock`：

| 类别 | 扩展名 | 说明 |
|---|---|---|
| 源文件 | `.psd` `.tif` `.tiff` `.exr` `.hdr` `.wav` `.aiff` | 手改的原始素材 |
| 模型 / 动画 | `.fbx` `.blend` `.max` `.ma` `.mb` | 无法三方合并 |
| 雕刻 / 材质 | `.ztl` `.spp` `.sbsar` `.sbs` | 同上 |
| 位图 | `.png` `.jpg` `.jpeg` `.tga` | **仅限工作资产目录** |

**截图目录不锁**（`Assets/Screenshots/`、`Screenshots/`）：那里是过程记录，加了锁文件会变只读，反而妨碍截图工具和 Unity 写入。

当前实际覆盖：**205 个文件**（其中 74 张角色/贴图 png）。

### 怎么用

已设 `needs-lock` 的文件在本地是**只读**的，保存会失败，必须先加锁：

```powershell
svn lock Assets/Characters/Lizhiyan/T_actor_lizhiyan_body_01_D.png
```

改完 `svn commit` 会自动释放锁；若提交时用了 `--no-unlock`，需手动 `svn unlock <file>`。

锁的意义：两个人同时改一张图，后提交的会把先提交的**直接覆盖**——这是美术协作最常见的灾难。Git 对此完全无能为力，这正是这个项目值得上 SVN 的理由。

场景 / prefab 的冲突由 Git 侧的 `merge=unityyamlmerge` 处理（见 `.gitattributes` 里的说明）。

---

## 7. 新同事上手

```powershell
git clone https://github.com/Theodore12342/UnityDemo.git URP_Projects
cd URP_Projects

# 没有这一步，Unity 打开后满屏粉色（资产全缺）
.\Tools\Setup-SvnArt.ps1 -RepoUrl https://svn.example.com/svn/urp-art
```

**必须写进 README**：只 clone Git 工程跑不起来。

---

## 8. CI / 打包机

```powershell
git clone <git-url> .
.\Tools\Setup-SvnArt.ps1 -RepoUrl $env:SVN_URL
```

SVN 凭据用 `--username` / `--password` 或 `--no-auth-cache`，别写进脚本。

---

## 9. 红线清单

1. **同一个文件不能被两边同时跟踪。** 改 `.gitignore` 必须同步改 `Tools/Setup-SvnArt.ps1` 的 `$ArtPaths`，反之亦然。
2. **不要文件级混排。** 切分点必须是"整个目录"（`Assets/Grass/Data` 这种子目录也算整体）。同一目录里一半在 Git 一半在 SVN，必然出事故。
3. **不要用 `svn:externals` 挂资产。** Unity 会扫到，但 externals 更新时机不受控，容易半检出。
4. **`.svn/` 绝不能进 Git**（已在 `.gitignore`）。
5. **SVN 服务器要单独备份。** 现在有两套版本库，别只备份 GitHub。
6. **分支不同步是固有痛点。** Git 的 feature 分支是局部的，SVN 工作副本是全局的——在分支上改的美术资产，切回 main 依然在。所以**美术改动尽量落在主干，别跟着代码分支走**。
7. **不要在 `Assets/` 或工程根上执行 `svn add`。** 现在每个美术目录是独立工作副本，那个命令在根目录只会报错——但别去试。

---

## 10. 以后要迁移怎么办

### 从本机试验库搬到正式服务器

⚠️ **`svn relocate` 只改工作副本的 URL 指向，不会搬运历史。** 换服务器要分两步：

**第一步：搬历史（三选一）**

```powershell
# 方式 A：dump / load（最通用，离线可行）
svnrdump dump file:///F:/svn/urp-art > F:\urp-art.dump
svnrdump load https://your.server/svn/urp-art < F:\urp-art.dump
# 若是老版本 svn，用：svnadmin dump F:\svn\urp-art > urp-art.dump

# 方式 B：svnsync（服务器之间镜像，逐版同步，可断点续传）
svnsync initialize https://your.server/svn/urp-art file:///F:/svn/urp-art --source-username x --source-password y
svnsync synchronize https://your.server/svn/urp-art

# 方式 C：只搬当前版本（不要历史，最快）
#   服务器上建空库 → 各工作副本 commit 一次即可，历史全丢
```

**第二步：让工作副本指向新地址**

```powershell
svn relocate https://your.server/svn/urp-art Assets/Textures
# 每个美术目录各执行一次（共 10 个）
```

`relocate` 只改 URL，本地未提交的改动全部保留。

### 只想先做冷备份（不建服务器）

```powershell
# 仓库是自包含目录，直接整目录复制即可，无需停机
robocopy F:\svn\urp-art D:\backup\svn-urp-art /MIR /R:1 /W:1
```

注意：**备份必须放在另一块物理盘或网络位置**。现在工作副本和仓库都在 F 盘，同一块盘上两份不等于备份。

### 合并回单一系统

- **转 Perforce / Unity VCS**：两边内容重新导入，`p4 import` 或 Unity VCS 迁移工具能直接吃 Git 仓库 + 目录树。
- **转纯 Git + LFS**：`git lfs migrate import --include="Assets/Textures/**,Assets/Characters/**"`，再把 SVN 的当前版本整体提交一次（历史会丢，但资产历史通常不值得保留）。

这套方案本质是**用两套工具换各自的强项**，代价是两套备份、两套权限、分支不同步。超过 3–5 人协作或美术迭代极频繁时，建议直接转 Perforce 或 Unity Version Control，把复杂度收回一套系统。

---

## 11. 自检清单

- [ ] `git ls-files | Select-String "Assets/Textures"` 无输出
- [ ] `git status --porcelain` 里看不到美术目录
- [ ] 每个美术目录下有 `.svn`，工程根和 `Assets/` 下**没有**
- [ ] `svn status` 里没有陌生的 `?`（尤其没有 `.csproj`、`Thumbs.db`）
- [ ] `svn propget svn:needs-lock <某个 png>` 返回 `*`
- [ ] Unity 打开工程，4 个场景正常加载、无粉色
- [ ] `git ls-files -o --exclude-standard` 统计体积在 5 MB 量级

---

## 12. 当前实际状态（2026-11-12）

| 项目 | 状态 |
|---|---|
| SVN 仓库 | `F:\svn\urp-art`（本机试验，`file://`），最新 **r25** |
| 仓库体积 | **2173 MB**（原始资产 2361 MB，SVN 有压缩） |
| 美术工作副本 | **10 个**，全部 `svn status` 干净 |
| 加锁文件 | **205 个**，只读已生效 |
| Git 提交 | `4b61752`，**327 个文件 / 4 MB** |
| Git 推送 | ⚠️ 未完成（当前网络无法访问 github.com），本地提交已就绪 |

### 推进过程中踩到并修掉的两个坑

1. **`svn commit -m "中文"` 在 Windows 会直接失败**
   `svn: E721113: Conversion from UTF-16 failed`。Windows 版 `svn.exe` 按控制台代码页处理命令行参数，非 ASCII 提交信息必然踩雷。
   → 脚本已改为写 UTF-8 无 BOM 临时文件，用 `-F <file>` 传消息。**手动提交带中文时也要这样**：

   ```powershell
   "art: 重绘裙摆贴图" | Out-File -FilePath msg.txt -Encoding utf8
   svn commit -F msg.txt Assets/Textures
   ```

2. **`core.autocrlf=true` 会把 `.meta` / `.unity` 转成 CRLF**
   这台机器开着 autocrlf，只写 `* text=auto` 的话，文本资产在工作区是 CRLF、库里是 LF，每次 checkout 都会制造"假改动"，甚至让 Unity 的 YAML 出现整文件 diff。
   → `.gitattributes` 首行改为 `* text=auto eol=lf`：文本一律 LF，二进制（`Grass.unity` 等）按内容识别后原样保留。已用 `git ls-files --eol` 验证：`.meta`/文本场景为 `i/lf`，`Grass.unity` 为 `i/-text`。

### 待办

```powershell
# 1. 联网后推送代码（美术资产不在这里，仓库只有 4 MB）
git push -u origin main

# 2. ⚠️ 美术资产目前只在本机 F 盘（工作副本 + 仓库同盘），先做冷备份到另一块盘
robocopy F:\svn\urp-art D:\backup\svn-urp-art /MIR /R:1 /W:1

# 3. 在 Unity 里逐个打开 4 个场景，确认无粉色材质、无 missing reference

# 4. 有正式 SVN 服务器后：先 dump/load 搬历史，再 relocate 改指向（见 §10）
svnrdump dump file:///F:/svn/urp-art > F:\urp-art.dump
svnrdump load https://your.server/svn/urp-art < F:\urp-art.dump
svn relocate https://your.server/svn/urp-art Assets/Textures
```
