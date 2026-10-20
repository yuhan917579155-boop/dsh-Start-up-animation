param(
  [ValidateSet('auto','web','desktop')][string]$Profile = 'auto',
  [string]$Exe = ''
)
$ErrorActionPreference = 'Stop'
$pkg = 'dsh-haavk'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Ok($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host ""; Write-Host "  [失败] $msg" -ForegroundColor Red; exit 1 }

Say ""
Say "  哈夫克开机动画 · 卸载" Cyan
Say "  ------------------------------------" DarkGray

$exe = $null
if ($Exe) { if (Test-Path -LiteralPath $Exe) { $exe = $Exe } else { Fail "指定的路径不存在：$Exe" } }
$proc = if (-not $exe) { Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1 } else { $null }
if ($proc) { $exe = $proc.Path }
if (-not $exe) {
  foreach ($c in @((Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe'), (Join-Path $env:ProgramFiles 'DeepSeek Harness\DeepSeek Harness.exe'))) {
    if (Test-Path -LiteralPath $c) { $exe = $c; break }
  }
}
$cli = $null
if ($exe) {
  $asar = Join-Path (Split-Path -Parent $exe) 'resources\app.asar'
  if (Test-Path -LiteralPath $asar) { $cli = Join-Path $asar 'dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js' }
}
$dsh = Get-Command dsh -ErrorAction SilentlyContinue | Select-Object -First 1

$target = $Profile
if ($target -eq 'auto') {
  if ($exe -and $cli) { $target = 'desktop' } elseif ($dsh) { $target = 'web' } else { Fail "没找到 DSH。" }
}

$ans = Read-Host "  确认卸载 dsh-haavk（会先关闭并重启 DSH）？[y/N]"
if ($ans -notmatch '^[Yy]') { Say "  已取消。"; exit 0 }

$running = @(Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue)
if ($target -eq 'desktop' -and $running.Count -gt 0) {
  $running | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

$log = Join-Path $env:TEMP ('dsh-haavk-remove-' + [guid]::NewGuid().ToString('N') + '.log')
$code = 1
if ($target -eq 'desktop') {
  $tmp = Join-Path $env:TEMP ('dsh-haavk-remove-' + [guid]::NewGuid().ToString('N') + '.cmd')
  Set-Content -LiteralPath $tmp -Value @(
    '@echo off',
    'chcp 65001 > nul',
    'set ELECTRON_RUN_AS_NODE=1',
    ('"' + $exe + '" --expose-internals "' + $cli + '" plugin --profile desktop remove ' + $pkg + ' > "' + $log + '" 2>&1'),
    'exit /b %ERRORLEVEL%'
  ) -Encoding Default
  & cmd.exe /c $tmp
  $code = $LASTEXITCODE
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
} else {
  & $dsh.Source plugin --profile web remove $pkg *> $log
  $code = $LASTEXITCODE
}

if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 10 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Say "    $_" DarkGray } }
if ($code -ne 0) { Fail "卸载失败（退出码 $code）。" }
Ok "已卸载，开机会恢复成 DSH 自己的启动画面"

if ($target -eq 'desktop' -and $exe) {
  try { Start-Process -FilePath $exe -ErrorAction Stop; Ok "已重新启动 DeepSeek Harness" } catch { Say "  请手动重新打开 DSH。" Yellow }
}
Say ""
