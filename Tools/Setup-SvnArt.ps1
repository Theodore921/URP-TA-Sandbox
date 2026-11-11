<#
.SYNOPSIS
    美术资产接入 SVN，Git 只管代码（Git + SVN 混合方案）。

.DESCRIPTION
    为每个美术目录建立独立的 SVN 工作副本（.svn 就在该目录内），
    而不是把工作副本根设在工程根。

    为什么这么设计：
      - 如果工作副本根在工程根或 Assets/，svn status 会把 Git 管的
        上千个文件全部报成 "?"，而且 svn add --parents 会把 Assets、
        Assets/Grass 也变成 SVN 版本化目录，两套系统就开始互相污染。
      - 独立工作副本让每个目录"只属于 SVN"，svn status 永远干净。

    脚本做四件事：
      1. 检查 svn 客户端
      2. 首次：在仓库里建好对应目录、checkout 到本地、把现有文件 add 进去
      3. 给源文件类资产打 svn:needs-lock，并设置 global-ignores
      4. 提交，然后复查 Git 侧有没有重复跟踪

.PARAMETER RepoUrl
    SVN 仓库根地址（不含 /trunk）。本地试验可用 file:///F:/svn/urp-art

.PARAMETER Import
    首次导入：把本地已有的美术文件提交进 SVN（会自动 commit）。

.PARAMETER Update
    日常更新：对每个美术目录执行 svn update，然后打印状态。

.PARAMETER ProjectRoot
    工程根目录，默认是本脚本的上一级目录。

.EXAMPLE
    .\Tools\Setup-SvnArt.ps1 -RepoUrl https://svn.example.com/svn/urp-art -Import

.EXAMPLE
    .\Tools\Setup-SvnArt.ps1 -RepoUrl https://svn.example.com/svn/urp-art

.EXAMPLE
    .\Tools\Setup-SvnArt.ps1 -Update
#>
[CmdletBinding(DefaultParameterSetName = 'Sync')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Sync')]
    [Parameter(Mandatory = $true, ParameterSetName = 'Import')]
    [string]$RepoUrl,

    [Parameter(Mandatory = $true, ParameterSetName = 'Import')]
    [switch]$Import,

    [Parameter(Mandatory = $true, ParameterSetName = 'Update')]
    [switch]$Update,

    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),

    [string]$Message = "chore: 同步美术资产"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------
# 必须与工程根 .gitignore 的"美术资产"一节完全一致
# ---------------------------------------------------------------
$ArtPaths = @(
    'Assets/TerrainSampleAssets'
    'Assets/Screenshots'
    'Assets/Characters'
    'Assets/Textures'
    'Assets/Models'
    'Assets/SkyCheck'
    'Assets/Animations'
    'Assets/Art'
    'Assets/Grass/Data'
    'Screenshots'
)

# 无法三方合并的源文件：编辑前必须 svn lock
$LockedExtensions = @(
    '.psd', '.tif', '.tiff', '.exr', '.hdr',
    '.fbx', '.blend', '.max', '.ma', '.mb',
    '.ztl', '.spp', '.sbsar', '.sbs', '.wav', '.aiff'
)

# 图片资产同样无法合并，也要锁；但截图目录只是过程记录，
# 加锁会把文件变成只读，反而妨碍 Unity / 截图工具写入，故排除。
$LockedImageExtensions = @('.png', '.jpg', '.jpeg', '.tga')
$NoLockPaths = @('Assets/Screenshots', 'Screenshots')

$GlobalIgnores = '*.csproj *.sln *.suo *.user *.pidb *.tmp *.log .vs .idea Thumbs.db desktop.ini .DS_Store'

function Write-Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "    $text" -ForegroundColor Green }
function Write-Warn2($text) { Write-Host "    $text" -ForegroundColor Yellow }
function Write-Dim($text) { Write-Host "    $text" -ForegroundColor DarkGray }

function New-SvnMessageFile([string]$text) {
    # 不要用 svn -m "中文"：Windows 版 svn.exe 会把参数按控制台代码页处理，
    # 非 ASCII 提交信息会直接报 E721113（Conversion from UTF-16 failed）。
    # 统一写 UTF-8 无 BOM 临时文件，再用 -F 传入。
    $f = Join-Path ([System.IO.Path]::GetTempPath()) ("svnmsg-" + [guid]::NewGuid().ToString('N') + ".txt")
    [System.IO.File]::WriteAllText($f, $text, (New-Object System.Text.UTF8Encoding($false)))
    return $f
}

function Invoke-Svn {
    # 注意：svn 把 warning 写到 stderr，而 $ErrorActionPreference = 'Stop' 下
    # 原生命令的 stderr 会被 PowerShell 变成终止性异常（NativeCommandError）。
    # 所以这里临时放宽，按退出码自己判断成功失败。
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & svn @args --non-interactive 2>&1
        return @{ Code = $LASTEXITCODE; Output = $out }
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
}

# ---------- 前置检查 ----------
if (-not (Get-Command svn -ErrorAction SilentlyContinue)) {
    throw @"
找不到 svn.exe。
请先安装以下任一客户端，安装后重开终端：
  - TortoiseSVN（安装时务必勾选 "command line client tools"）
  - 官方 Apache Subversion for Windows
"@
}

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "工程根目录不存在：$ProjectRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
    Write-Warn2 "注意：$ProjectRoot 看起来不是 Git 仓库根，确认路径是否正确。"
}

if ($Update) {
    # ---------------- 日常更新 ----------------
    Write-Step "更新全部美术工作副本"
    $found = 0
    foreach ($rel in $ArtPaths) {
        $full = Join-Path $ProjectRoot $rel
        if (-not (Test-Path -LiteralPath (Join-Path $full '.svn'))) {
            Write-Dim "未初始化，跳过：$rel"
            continue
        }
        $r = Invoke-Svn update $full
        if ($r.Code -eq 0) { Write-Ok "$rel" } else { Write-Warn2 "$rel 更新失败：$($r.Output)" }
        $found++
    }
    if ($found -eq 0) { Write-Warn2 "没有任何美术目录是工作副本，请先不带 -Update 跑一次初始化。" }
    Write-Host "`n完成。" -ForegroundColor Cyan
    return
}

$RepoUrl = $RepoUrl.TrimEnd('/')
$TrunkUrl = "$RepoUrl/trunk"

Write-Step "检查 svn 客户端"
Write-Ok ("svn " + (svn --version --quiet) + "  (" + (Get-Command svn).Source + ")")

# ---------- 1. 确保 trunk 存在 ----------
Write-Step "检查 trunk"
$r = Invoke-Svn info $TrunkUrl
if ($r.Code -ne 0) {
    Write-Ok "trunk 不存在，创建中"
    $mf = New-SvnMessageFile "init: trunk"
    $r = Invoke-Svn mkdir --parents $TrunkUrl -F $mf
    Remove-Item -LiteralPath $mf -Force -ErrorAction SilentlyContinue
    if ($r.Code -ne 0) { throw "创建 trunk 失败，检查地址与凭据：$TrunkUrl`n$($r.Output)" }
} else {
    Write-Ok $TrunkUrl
}

# ---------- 2. 逐个目录：建库 → checkout → add ----------
Write-Step "处理 $($ArtPaths.Count) 个美术目录"
$touched = @()

foreach ($rel in $ArtPaths) {
    $full = Join-Path $ProjectRoot $rel
    $svnPath = $rel.Replace('\', '/')
    $url = "$TrunkUrl/$svnPath"

    Write-Host ""
    Write-Host "  [$rel]" -ForegroundColor White

    if (Test-Path -LiteralPath (Join-Path $full '.svn')) {
        Write-Ok "已是工作副本，执行 update"
        $r = Invoke-Svn update $full
        if ($r.Code -ne 0) { Write-Warn2 $r.Output; continue }
        $touched += $full
        continue
    }

    # 确保仓库里这个目录存在
    $r = Invoke-Svn info $url
    if ($r.Code -ne 0) {
        $mf = New-SvnMessageFile "init: $svnPath"
        $r = Invoke-Svn mkdir --parents $url -F $mf
        Remove-Item -LiteralPath $mf -Force -ErrorAction SilentlyContinue
        if ($r.Code -ne 0) { Write-Warn2 "建库目录失败：$($r.Output)"; continue }
        Write-Dim "仓库目录已创建：$svnPath"
    }

    if (-not (Test-Path -LiteralPath $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
        Write-Dim "本地目录原不存在，已创建空目录"
    }

    $r = Invoke-Svn checkout $url $full
    if ($r.Code -ne 0) { Write-Warn2 "checkout 失败：$($r.Output)"; continue }
    Write-Ok "checkout 完成"

    if ($Import) {
        $r = Invoke-Svn add --force $full
        if ($r.Code -ne 0) { Write-Warn2 "add 警告：$($r.Output)" }

        $st = Invoke-Svn status $full
        $added = @($st.Output | Where-Object { $_ -match '^A' })
        Write-Ok "已 add $($added.Count) 项"

        # global-ignores：忽略各系统/工具产生的垃圾
        Invoke-Svn propset svn:global-ignores $GlobalIgnores $full | Out-Null
    }

    $touched += $full
}

# ---------- 3. 加锁属性 ----------
if ($Import -and $touched.Count -gt 0) {
    Write-Step "设置 svn:needs-lock（源文件类资产）"
    $lockTargets = @()
    foreach ($full in $touched) {
        $relFull = $full.Replace($ProjectRoot + '\', '').Replace('\', '/')
        $isNoLock = @($NoLockPaths | Where-Object { $relFull -eq $_ -or $relFull.StartsWith("$_/") }).Count -gt 0
        $exts = $LockedExtensions
        if (-not $isNoLock) { $exts = $LockedExtensions + $LockedImageExtensions }

        $lockTargets += Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $exts -contains $_.Extension.ToLower() } |
            ForEach-Object { $_.FullName }
    }

    if ($lockTargets.Count -gt 0) {
        $batch = 80
        for ($i = 0; $i -lt $lockTargets.Count; $i += $batch) {
            $end = [Math]::Min($i + $batch - 1, $lockTargets.Count - 1)
            $slice = $lockTargets[$i..$end]
            Invoke-Svn propset svn:needs-lock yes @slice | Out-Null
        }
        Write-Ok "$($lockTargets.Count) 个文件已加锁属性"
    } else {
        Write-Warn2 "没有匹配的源文件类型"
    }

    # ---------- 4. 提交 ----------
    Write-Step "提交到 SVN"
    foreach ($full in $touched) {
        $rel = $full.Replace($ProjectRoot + '\', '')
        $mf = New-SvnMessageFile "$Message ($rel)"
        $r = Invoke-Svn commit $full -F $mf
        Remove-Item -LiteralPath $mf -Force -ErrorAction SilentlyContinue
        if ($r.Code -eq 0) {
            Write-Ok "committed: $rel"
        } else {
            Write-Warn2 "$rel 提交失败（可能没有改动）：$($r.Output)"
        }
    }
}

# ---------- 5. Git 侧复查 ----------
Write-Step "Git 侧复查"
Push-Location $ProjectRoot
try {
    $tracked = @(git ls-files)
    $overlap = @()
    foreach ($rel in $ArtPaths) {
        $prefix = $rel.Replace('\', '/') + '/'
        $overlap += $tracked | Where-Object { $_.StartsWith($prefix) }
    }

    if ($overlap.Count -gt 0) {
        Write-Warn2 "以下 $($overlap.Count) 个文件仍被 Git 跟踪，必须解除："
        $overlap | Select-Object -First 10 | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        Write-Host "    执行：" -ForegroundColor White
        foreach ($rel in $ArtPaths) {
            Write-Host "      git rm -r --cached `"$($rel.Replace('\','/'))`"" -ForegroundColor White
        }
    } else {
        Write-Ok "Git 没有跟踪任何美术目录，切分干净"
    }

    $pending = @(git ls-files -o --exclude-standard)
    $sum = [int64]0
    foreach ($f in $pending) {
        $p = Join-Path $ProjectRoot $f
        if (Test-Path -LiteralPath $p) { $sum += (Get-Item -LiteralPath $p -Force).Length }
    }
    Write-Ok ("Git 侧待提交：{0} 个文件，{1} MB" -f $pending.Count, [Math]::Round($sum / 1MB, 1))
}
finally {
    Pop-Location
}

Write-Host @"

完成。
  日常更新资产：.\Tools\Setup-SvnArt.ps1 -Update
  改完资产提交：svn commit -m "art: ..." Assets/Textures
  完整流程见 VERSION_CONTROL.md
"@ -ForegroundColor Cyan
