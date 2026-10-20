param(
  [ValidateSet('auto','web','desktop')][string]$Profile = 'auto',
  [string]$Exe = '',
  [switch]$NoRestart,
  [switch]$NoStop,
  [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tgz  = Join-Path $here 'plugin\dsh-haavk-1.8.0-fullscreen.tgz'
$pkg  = 'dsh-haavk'
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$stableDir = Join-Path $dshHome 'plugins'
$stable = Join-Path $stableDir 'dsh-haavk-1.8.0-fullscreen.tgz'
$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Ok($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host ""; Write-Host "  [失败] $msg" -ForegroundColor Red; exit 1 }

Say ""
Say "  哈夫克开机动画 · DSH 插件安装器" Cyan
Say "  ------------------------------------" DarkGray

if (-not (Test-Path -LiteralPath $tgz)) {
  Fail "找不到插件包：$tgz"
}

# 1) 找桌面版
$exe = $null
if ($Exe) { if (Test-Path -LiteralPath $Exe) { $exe = $Exe } else { Fail "指定的路径不存在：$Exe" } }
$proc = if (-not $exe) { Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1 } else { $null }
if ($proc) { $exe = $proc.Path }
if (-not $exe) {
  $cands = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe'),
    (Join-Path $env:ProgramFiles 'DeepSeek Harness\DeepSeek Harness.exe')
  )
  if ($pf86) { $cands += (Join-Path $pf86 'DeepSeek Harness\DeepSeek Harness.exe') }
  foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $exe = $c; break } }
}
if (-not $exe) {
  foreach ($r in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    if (-not (Test-Path $r)) { continue }
    $hit = Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } | Where-Object { $_.DisplayName -like '*DeepSeek Harness*' -and $_.InstallLocation } | Select-Object -First 1
    if ($hit) {
      $c = Join-Path $hit.InstallLocation 'DeepSeek Harness.exe'
      if (Test-Path -LiteralPath $c) { $exe = $c; break }
    }
  }
}

$cli = $null
if ($exe) {
  $asar = Join-Path (Split-Path -Parent $exe) 'resources\app.asar'
  if (Test-Path -LiteralPath $asar) { $cli = Join-Path $asar 'dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js' }
}
$dsh = Get-Command dsh -ErrorAction SilentlyContinue | Select-Object -First 1

# 2) 决定装到哪个 profile
$target = $Profile
if ($target -eq 'auto') {
  if ($exe -and $cli) { $target = 'desktop' }
  elseif ($dsh) { $target = 'web' }
  else { Fail "没找到桌面版 DeepSeek Harness，也没找到命令行版 dsh。请确认 DSH 已安装。" }
}
if ($target -eq 'desktop' -and (-not $exe -or -not $cli)) { Fail "没找到桌面版安装位置。可以试试：安装.cmd -Profile web" }
if ($target -eq 'web' -and -not $dsh) { Fail "没找到 dsh 命令。命令行版请先 npm i -g @deepseek-ai/dsh。" }

if ($target -eq 'desktop') {
  Say ""
  Say "  目标：桌面版 desktop profile" DarkCyan
  Say "  $exe" DarkGray
} else {
  Say ""
  Say "  目标：命令行版 web profile" DarkCyan
  Say "  $($dsh.Source)" DarkGray
}

if ($CheckOnly) { Ok "环境检查通过（自检模式，未做任何改动）"; exit 0 }

# 3) 桌面版要先完全退出（profile 被进程锁着）
$running = @(Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue)
if ($target -eq 'desktop' -and $running.Count -gt 0 -and -not $NoStop) {
  Say ""
  Say "  安装前需要完全退出 DeepSeek Harness（当前 $($running.Count) 个进程在跑）。" Yellow
  $ans = Read-Host "  现在自动关闭它、装完再自动打开？[Y/n]"
  if ($ans -and $ans -notmatch '^[Yy]') { Fail "已取消。请手动退出桌面端后重新运行 安装.cmd。" }
  $running | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  if (@(Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue).Count -gt 0) { Fail "桌面端没有完全退出，请手动退出后重试。" }
}

# 4) 先放到稳定位置再装（不依赖解压出来的临时目录）
New-Item -ItemType Directory -Force -Path $stableDir | Out-Null
Copy-Item -LiteralPath $tgz -Destination $stable -Force
Ok "插件包已复制到 $stable"

$log  = Join-Path $env:TEMP ('dsh-haavk-install-' + [guid]::NewGuid().ToString('N') + '.log')
$code = 1
if ($target -eq 'desktop') {
  $tmp = Join-Path $env:TEMP ('dsh-haavk-install-' + [guid]::NewGuid().ToString('N') + '.cmd')
  Set-Content -LiteralPath $tmp -Value @(
    '@echo off',
    'chcp 65001 > nul',
    'set ELECTRON_RUN_AS_NODE=1',
    ('"' + $exe + '" --expose-internals "' + $cli + '" plugin --profile desktop add "' + $stable + '" > "' + $log + '" 2>&1'),
    'exit /b %ERRORLEVEL%'
  ) -Encoding Default
  & cmd.exe /c $tmp
  $code = $LASTEXITCODE
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
} else {
  & $dsh.Source plugin --profile web add $stable *> $log
  $code = $LASTEXITCODE
}

if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 14 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Say "    $_" DarkGray } }
if ($code -ne 0) { Fail "安装失败（退出码 $code）。把上面这段输出发给我。" }
Ok "已安装 dsh-haavk 到 $target profile"

# 5) 重新打开
if ($target -eq 'desktop' -and -not $NoRestart) {
  try { Start-Process -FilePath $exe -ErrorAction Stop; Ok "已重新启动 DeepSeek Harness" }
  catch { Say "  请手动重新打开 DeepSeek Harness。" Yellow }
}

Say ""
Say "  装好了。接下来：" Cyan
Say "   1) DSH 需要「完全退出后重新打开」才会加载（安装器已替你重启）"
Say "   2) 冷启动会播一段哈夫克开机动画，按 Esc 或点画面可跳过"
Say "   3) 想改档位 / 音量 / 身份名： 设置 → 启动动画"
Say ""
Say "  注意：默认是静音的，「界面音效」和「语音播报」两个开关要自己在设置里打开。" DarkYellow
Say ""
