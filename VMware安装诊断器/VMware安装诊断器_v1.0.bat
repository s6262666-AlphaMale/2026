@echo off
chcp 936 >nul
title VMware 安装诊断器 v1.0
rem ===========================================================================
rem  VMware 安装诊断器 v1.0
rem  用法：把本文件和 VMware 安装包放在同一文件夹（或下载/桌面），双击运行。
rem        脚本会自动提权 → 运行 VMware 安装程序 → 安装结束/闪退后自动采集证据，
rem        生成「诊断报告.txt」并复制到剪贴板，直接 Ctrl+V 发给 Claude 即可。
rem  报告位置：H:\Claude Code MCP\VMware诊断_时间戳\（该盘不存在则放在本 bat 旁边）
rem  本文件编码：GBK + CRLF，请勿用记事本另存为 UTF-8，否则中文会乱码。
rem ===========================================================================
set "VMDIAG_BAT=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$m='::'+'PS_START'; $s=[IO.File]::ReadAllText($env:VMDIAG_BAT,[Text.Encoding]::GetEncoding(936)); iex ($s.Substring($s.IndexOf($m)+$m.Length))"
exit /b
::PS_START
# ============================================================================
#  以下为 PowerShell 代码，由上方 bat 读取执行（cmd 执行到 exit /b 就结束，不会解析到这里）
#  流程：提权 → 安装前残留快照 → 运行安装程序 → 启动测试 → 采集证据 → 自动初判 → 出报告
# ============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$VER    = 'v1.0'
$BAT    = $env:VMDIAG_BAT
$tStart = Get-Date
try { $Host.UI.RawUI.WindowTitle = "VMware 安装诊断器 $VER" } catch {}
function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }

# ---------- 0. 管理员权限：不足则自动提权，在新窗口重开 ----------
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Say '需要管理员权限（读取驱动、事件日志），正在请求提权，请在弹窗中点「是」……' 'Yellow'
    $lit  = "'" + ($BAT -replace "'", "''") + "'"
    $boot = "`$env:VMDIAG_BAT=$lit; `$m='::'+'PS_START'; `$s=[IO.File]::ReadAllText(`$env:VMDIAG_BAT,[Text.Encoding]::GetEncoding(936)); iex (`$s.Substring(`$s.IndexOf(`$m)+`$m.Length))"
    $enc  = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($boot))
    try {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc" -ErrorAction Stop
    } catch {
        Say '未获得管理员权限，无法继续。请右键本 bat →「以管理员身份运行」。' 'Red'
        Read-Host '按回车键退出' | Out-Null
    }
    return
}

# ---------- 通用工具 ----------
$S     = @{}                                              # 自动初判用的判据
$Hints = New-Object System.Collections.Generic.List[string]
$RB    = New-Object System.Text.StringBuilder              # 报告正文
function Rep([string]$t) { [void]$RB.AppendLine($t) }
function Hint([string]$t) { $Hints.Add($t) }
function Sec([string]$title, [scriptblock]$body) {
    Rep ''; Rep ('=' * 76); Rep "【$title】"; Rep ('=' * 76)
    $buf = New-Object System.Collections.Generic.List[object]; $fail = $null
    try { & $body 2>&1 | ForEach-Object { $buf.Add($_) } } catch { $fail = $_.Exception.Message }   # 出错也保留已采集的部分
    $o = ($buf | Out-String -Width 260).TrimEnd()
    if ($o) { Rep $o } elseif (-not $fail) { Rep '  (无)' }
    if ($fail) { Rep "  (本节后续采集失败: $fail)" }
}
function Tbl($o) {
    if ($o) { ($o | Format-Table -AutoSize -Wrap | Out-String -Width 250).TrimEnd() } else { '  (无)' }
}
function Cut([string]$s, [int]$n = 300) { if ($s.Length -gt $n) { $s.Substring(0, $n) + ' …' } else { $s } }
function Get-Ev([hashtable]$f, [int]$max = 40) {
    try { @(Get-WinEvent -FilterHashtable $f -MaxEvents $max -ErrorAction Stop) } catch { @() }
}
function Fmt-Ev($e, [int]$cut = 1500) {
    $m = $e.Message
    if (-not $m) { $m = (@($e.Properties | ForEach-Object { $_.Value }) -join ' | ') }
    $m = ($m -replace '(\r?\n)+', "`n").Trim()
    if ($m.Length -gt $cut) { $m = $m.Substring(0, $cut) + ' …(截断)' }
    "[$($e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))] $($e.ProviderName)  事件ID $($e.Id)  $($e.LevelDisplayName)`n$m`n"
}
function Read-Shared([string]$p) {
    try {
        $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::GetEncoding(936), $true)
        $t  = $sr.ReadToEnd(); $sr.Close(); $t
    } catch { "(无法读取: $($_.Exception.Message))" }
}
function Copy-Shared([string]$src, [string]$dst) {
    try {
        $i = [IO.File]::Open($src, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
        $o = [IO.File]::Create($dst); $i.CopyTo($o); $o.Close(); $i.Close()
    } catch {}
}
function Excerpt([string]$text) {
    $L = $text -split '\r?\n'
    $o = New-Object System.Collections.Generic.List[string]
    $rv = -1
    for ($i = 0; $i -lt $L.Count; $i++) { if ($L[$i] -match 'Return value 3') { $rv = $i; break } }
    if ($rv -ge 0) {
        $o.Add('--- MSI 首个失败点「Return value 3」之前 30 行 ---')
        $s0 = [Math]::Max(0, $rv - 30)
        foreach ($x in $L[$s0..$rv]) { $o.Add((Cut $x)) }
    }
    $err = @($L | Where-Object {
            $_ -match '(?i)error|fail|exception|panic|denied|1603|失败|错误|拒绝' -and
            $_ -notmatch '(?i)Note: 1: (2205|2228|1402|2262)|PROPERTY CHANGE|Property\(|ErrorDialog|ErrorIcon|IgnoreErrors' } |
        Select-Object -Last 30)
    if ($err.Count) { $o.Add('--- 错误关键词行（最后 30 条）---'); foreach ($x in $err) { $o.Add((Cut $x)) } }
    $o.Add('--- 结尾 25 行 ---')
    foreach ($x in @($L | Select-Object -Last 25)) { $o.Add((Cut $x)) }
    $o -join "`n"
}
function Fmt-Exit($c) {
    if ($null -eq $c) { return '未取到' }
    $u   = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$c), 0)
    $hex = '0x' + $u.ToString('X8')
    $map = @{ 0 = '正常结束'; 1 = '一般错误'; 1602 = '用户取消安装'; 1603 = '安装过程致命错误（看安装日志摘录）'
              1618 = '另一个安装程序正在运行'; 1638 = '已安装了该产品的另一个版本'; 3010 = '安装成功，需要重启'; 1641 = '安装成功，已发起重启' }
    $crash = @{ '0xC0000005' = '访问冲突崩溃（非法内存访问）'; '0xC0000409' = '安全检查失败崩溃（常见于注入 DLL 或运行库损坏）'
                '0xC0000135' = '缺少 DLL'; '0xC0000142' = 'DLL 初始化失败'; '0xC000007B' = '映像格式错误（32/64 位 DLL 错配，运行库损坏）'
                '0xE0434352' = '.NET 未处理异常'; '0xC0000374' = '堆损坏'; '0x40010004' = '进程被强制结束'; '0xC000013A' = '窗口被关闭/Ctrl+C' }
    if ($map.ContainsKey([int]$c)) { $t = $map[[int]$c] } elseif ($crash.ContainsKey($hex)) { $t = $crash[$hex] }
    elseif ([int]$c -lt 0) { $t = '异常终止（崩溃类错误码）' } else { $t = '未知' }
    "$c ($hex) → $t"
}
function Diagnose-Module($app, $mod, $code) {
    $m = "$mod".ToLower()
    $b = "崩溃进程 $app，出错模块 $mod，异常码 0x$code"
    if ($m -match '^(msvcp140|vcruntime140|vcruntime140_1|ucrtbase|concrt140|msvcr\d+)\.dll$') { return "$b → VC++ 运行库损坏：修复/重装 VC++ 2015-2022 的 x64 与 x86 两个版本。" }
    if ($m -match '^(ntdll|kernelbase|kernel32)\.dll$')  { return "$b → 系统通用崩溃点，需结合其他线索（残留 / Hyper-V / 注入模块）判断。" }
    if ($m -match '^(clr|clrjit|coreclr|mscorlib)')        { return "$b → .NET 运行时问题：修复 .NET Framework 4.8。" }
    if ($m -match '^(nvoglv|nvwgf|nvd3d|atio|atig|atidx|amdxx|igd|igxx|ig\d)') { return "$b → 显卡驱动崩溃：更新显卡驱动。" }
    if ($m -match '^(vm|libcef|glib|gobject|gtk|gdk|cairo|pango|libxml|sigc)') { return "$b → VMware 自身模块崩溃：多为旧配置残留或与 Hyper-V / 内存完整性冲突。" }
    if (-not $m -or $m -eq 'unknown') { return "$b → 模块未知：常见于第三方注入或内存保护拦截。" }
    "$b → 非系统、非 VMware 模块，疑似第三方软件注入（输入法 / 安全软件 / 加速器 / 录屏），请退出或卸载对应软件。"
}
$UninstKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
function Get-Uninst([string]$rx) {
    @(Get-ItemProperty -Path $UninstKeys -EA 0 | Where-Object { $_.DisplayName -match $rx } |
      Select-Object DisplayName, DisplayVersion, InstallLocation)
}
function Get-VMSvc {
    $all = @(Get-CimInstance Win32_Service -EA 0) + @(Get-CimInstance Win32_SystemDriver -EA 0)
    @($all | Where-Object { $_.Name -match '^(?i)(vmx86|hcmon|vmci|vmnet|vmusb|VMAuthd|VMUSBArb|VMware)' -or
                            $_.PathName -match '(?i)\\VMware\\|vmx86\.sys|hcmon\.sys|vmnetadapter|vmnetbridge|vmnetuserif' } |
      Select-Object Name, State, StartMode,
        @{ n = '类型'; e = { if ($_.CimClass.CimClassName -eq 'Win32_SystemDriver') { '驱动' } else { '服务' } } }, PathName)
}
$VMDirs = @("${env:ProgramFiles(x86)}\VMware", "$env:ProgramFiles\VMware", "$env:ProgramData\VMware", "$env:APPDATA\VMware")
function Get-VMDirs { @(foreach ($d in $VMDirs) { [pscustomobject]@{ '目录' = $d; '存在' = $(if (Test-Path -LiteralPath $d) { '是' } else { '否' }) } }) }
function Find-VMExe {
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Workstation', 'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation',
                   'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.\VMware Player', 'HKLM:\SOFTWARE\VMware, Inc.\VMware Player') {
        $ip = (Get-ItemProperty -LiteralPath $k -EA 0).InstallPath
        if ($ip) { foreach ($n in 'vmware.exe', 'vmplayer.exe') { $c = Join-Path $ip $n; if (Test-Path -LiteralPath $c) { return $c } } }
    }
    foreach ($c in "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmware.exe", "${env:ProgramFiles(x86)}\VMware\VMware Player\vmplayer.exe",
                   "$env:ProgramFiles\VMware\VMware Workstation\vmware.exe") { if (Test-Path -LiteralPath $c) { return $c } }
    $null
}
function Get-PendingReboot {
    $r = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $r += '组件更新待重启'; $S.pendingReboot = $true }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $r += 'Windows 更新待重启'; $S.pendingReboot = $true }
    $pfr = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA 0).PendingFileRenameOperations
    if ($pfr) { $r += "待替换文件 $(@($pfr).Count) 项" }
    if ($r) { $r -join '；' } else { '无' }
}

# ---------- MSI 详细日志策略：临时开启，结束后还原（异常退出的残留下次运行自动还原）----------
$diagRoot = Join-Path $env:SystemDrive 'VMDiag_Temp'
$stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$runTemp  = Join-Path $diagRoot "run_$stamp"
$marker   = Join-Path $diagRoot 'msilog_restore.txt'
$polKey   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer'
function Restore-MsiLogging {
    if (-not (Test-Path -LiteralPath $marker)) { return }
    $old = "$(Get-Content -LiteralPath $marker -Raw -EA 0)".Trim()
    if (-not $old -or $old -eq '<none>') { Remove-ItemProperty -LiteralPath $polKey -Name Logging -EA 0 }
    else { New-ItemProperty -LiteralPath $polKey -Name Logging -Value $old -PropertyType String -Force | Out-Null }
    Remove-Item -LiteralPath $marker -Force -EA 0
}
function Enable-MsiLogging {
    Restore-MsiLogging
    $old = (Get-ItemProperty -LiteralPath $polKey -Name Logging -EA 0).Logging
    if (-not $old) { $old = '<none>' }
    [IO.File]::WriteAllText($marker, $old)
    if (-not (Test-Path -LiteralPath $polKey)) { New-Item -Path $polKey -Force -EA 0 | Out-Null }
    New-ItemProperty -LiteralPath $polKey -Name Logging -Value 'voicewarmupx' -PropertyType String -Force | Out-Null
}

try {
    New-Item -ItemType Directory -Path $diagRoot -Force | Out-Null
    Restore-MsiLogging
    $origTemp = $env:TEMP; $origTmp = $env:TMP
    $batDir   = [IO.Path]::GetDirectoryName($BAT)

    # 报告输出目录：优先 H:\Claude Code MCP，其次 bat 所在目录，再次桌面
    $outBase = $null
    foreach ($d in @('H:\Claude Code MCP', $batDir, [Environment]::GetFolderPath('Desktop'))) {
        if ($d -and (Test-Path -LiteralPath $d)) {
            try { $pr = Join-Path $d ".vmdiag_probe_$stamp"; [IO.File]::WriteAllText($pr, 'x'); Remove-Item -LiteralPath $pr -Force; $outBase = $d; break } catch {}
        }
    }
    if (-not $outBase) { $outBase = $diagRoot }
    $outDir = Join-Path $outBase "VMware诊断_$stamp"
    $rawDir = Join-Path $outDir '原始日志'
    New-Item -ItemType Directory -Path $rawDir -Force | Out-Null

    Say ''
    Say "  ==============  VMware 安装诊断器 $VER  ==============" 'Cyan'
    Say '  安装过程中请不要点击/选中本窗口里的文字（会让脚本暂停）。' 'DarkYellow'
    Say ''

    # ---------- 1. 安装前残留快照 ----------
    Say '[1/5] 安装前快照：检查 VMware 残留……' 'Cyan'
    $pre = @{}
    $pre.Uninst = Get-Uninst 'VMware'
    $pre.Svc    = Get-VMSvc
    $pre.Dirs   = Get-VMDirs
    $pre.Proc   = @(Get-Process -EA 0 | Where-Object { $_.ProcessName -match '^(?i)(vmware|vmplayer|vmnat|vmnetdhcp)' } | Select-Object ProcessName, Id)
    $S.preInstalled = ($pre.Uninst.Count -gt 0)
    $S.preResidue   = (-not $S.preInstalled) -and (($pre.Svc.Count -gt 0) -or (@($pre.Dirs | Where-Object { $_.'存在' -eq '是' }).Count -gt 0))
    if ($S.preResidue) { Say '      发现旧版残留（无登记产品但有服务/驱动/目录）。' 'Yellow' }

    # ---------- 2. 定位安装程序 ----------
    Say '[2/5] 定位 VMware 安装程序……' 'Cyan'
    $inst = $null
    $dl = $null; try { $dl = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch {}
    $searchDirs = @($batDir, $dl, "$env:USERPROFILE\Downloads", [Environment]::GetFolderPath('Desktop'), 'H:\Claude Code MCP') |
                  Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    $cands = @(@(foreach ($d in $searchDirs) {
                Get-ChildItem -LiteralPath $d -File -EA 0 | Where-Object { $_.Name -match '^(?i)VMware-(workstation|player).*\.exe$' }
             }) | Sort-Object LastWriteTime -Descending)
    if ($cands.Count -gt 0) {
        $inst = $cands[0].FullName
        if ($cands.Count -gt 1) { Say "      找到 $($cands.Count) 个安装包，使用最新的一个：" 'Gray' }
        Say "      $inst" 'White'
    } else {
        Say '      未自动找到（文件名形如 VMware-workstation-full-*.exe），请在弹出窗口中手动选择。' 'Yellow'
        Say '      直接点「取消」= 不安装，只做「启动闪退」检测 + 采集。' 'Yellow'
        Add-Type -AssemblyName System.Windows.Forms
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = '请选择 VMware 安装程序（取消 = 只做检测）'
        $dlg.Filter = '安装程序 (*.exe)|*.exe'
        if ($dl) { $dlg.InitialDirectory = $dl }
        if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { $inst = $dlg.FileName }
        $owner.Dispose()
    }

    # ---------- 3. 运行安装程序 ----------
    $t0 = $null; $t1 = $null
    if ($inst) {
        Say '[3/5] 启动安装程序……' 'Cyan'
        Say '      请像平时一样操作安装界面。无论成功、报错还是闪退，安装程序退出后脚本都会自动继续。' 'White'
        Say '      如出现报错弹窗，先截图再点关闭。' 'White'
        New-Item -ItemType Directory -Path $runTemp -Force | Out-Null
        Enable-MsiLogging
        $t0 = Get-Date
        try {
            $env:TEMP = $runTemp; $env:TMP = $runTemp          # 纯英文临时目录：规避中文用户名路径 + 集中收集安装日志
            $psi = New-Object Diagnostics.ProcessStartInfo
            $psi.FileName = $inst
            $psi.WorkingDirectory = [IO.Path]::GetDirectoryName($inst)
            $psi.UseShellExecute = $false
            $p = [Diagnostics.Process]::Start($psi)
            $null = $p.Handle
            $p.WaitForExit()
            $S.exit = $p.ExitCode
            # 引导程序可能把真正的安装程序解压到临时目录再拉起，等它们也结束
            $deadline = (Get-Date).AddMinutes(60)
            do {
                $kids = @(Get-CimInstance Win32_Process -EA 0 | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($runTemp, [StringComparison]::OrdinalIgnoreCase) })
                if ($kids.Count) { Start-Sleep -Seconds 2 }
            } while ($kids.Count -and (Get-Date) -lt $deadline)
        } catch {
            $S.startErr = $_.Exception.Message
        } finally {
            $env:TEMP = $origTemp; $env:TMP = $origTmp
            Restore-MsiLogging
        }
        $t1 = Get-Date
        if ($null -ne $S.exit) { $S.exitCrash = ([int]$S.exit -lt 0) -or ([int]$S.exit -eq 1073807364) }
        if ($S.startErr) { Say "      安装程序无法启动：$($S.startErr)" 'Red' }
        else { Say "      安装程序已退出，退出码 $(Fmt-Exit $S.exit)" $(if ($S.exit -eq 0 -or $S.exit -eq 3010) { 'Green' } else { 'Red' }) }
    } else {
        Say '[3/5] 未选择安装程序，跳过安装（仅检测模式）。' 'Yellow'
    }
    $tE = if ($t0) { $t0.AddMinutes(-1) } else { $tStart.AddMinutes(-10) }

    # ---------- 4. 启动测试（检测「装好后一打开就闪退」）----------
    Say '[4/5] 启动测试……' 'Cyan'
    $S.launch = '未执行'
    $vmExe = Find-VMExe
    if (-not $vmExe) {
        $S.launch = '未找到 vmware.exe / vmplayer.exe（未安装成功），跳过'
        Say "      $($S.launch)" 'Yellow'
    } else {
        $yes = $true
        try { choice /c YN /t 20 /d Y /m '      检测到已安装的 VMware，是否自动打开一次检测「启动闪退」？20 秒后默认 Y'; $yes = ($LASTEXITCODE -ne 2) } catch {}
        if ($yes) {
            $name   = [IO.Path]::GetFileNameWithoutExtension($vmExe)
            $before = @(Get-Process -Name $name -EA 0 | ForEach-Object { $_.Id })
            if ($before.Count) {
                $S.launch = "$name 已在运行，跳过启动测试"
            } else {
                Say '      正在以普通权限打开 VMware，观察 30 秒，请不要手动关闭它……' 'White'
                $tL = Get-Date
                Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList ('"' + $vmExe + '"')
                $seen = $false; $gone = $false
                while (((Get-Date) - $tL).TotalSeconds -lt 30) {
                    if (@(Get-Process -Name $name -EA 0).Count) { $seen = $true } elseif ($seen) { $gone = $true; break }
                    Start-Sleep -Milliseconds 500
                }
                $life = [int]((Get-Date) - $tL).TotalSeconds
                if (-not $seen)  { $S.launch = '30 秒内未出现 VMware 进程 → 疑似瞬间闪退或被拦截'; $S.launchBad = $true }
                elseif ($gone)   { $S.launch = "VMware 进程在约 $life 秒后退出 → 疑似启动闪退（如果是你手动关的请忽略）"; $S.launchBad = $true }
                else             { $S.launch = 'VMware 持续运行 30 秒以上 → 启动正常（窗口可自行关闭）' }
            }
        } else { $S.launch = '用户选择跳过' }
        Say "      $($S.launch)" $(if ($S.launchBad) { 'Red' } else { 'Green' })
    }

    # ---------- 5. 采集证据 ----------
    Say '[5/5] 采集证据中（约 1 分钟，扫描驱动库较慢，请稍候）……' 'Cyan'

    Sec '基本信息' {
        $os  = Get-CimInstance Win32_OperatingSystem
        $cv  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA 0
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $cs  = Get-CimInstance Win32_ComputerSystem
        $dsk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
        $S.build  = [int]$os.BuildNumber
        $S.freeGB = [math]::Round($dsk.FreeSpace / 1GB, 1)
        $S.nonAsciiUser = ($env:USERNAME -match '[^\x00-\x7F]') -or ($origTemp -match '[^\x00-\x7F]')
        $gpu = (@(Get-CimInstance Win32_VideoController -EA 0 | ForEach-Object { "$($_.Name)（驱动 $($_.DriverVersion)）" }) -join '；')
        "系统            : $($os.Caption) $($cv.DisplayVersion)  内部版本 $($os.BuildNumber).$($cv.UBR)  $($os.OSArchitecture)"
        "语言 / 代码页   : $((Get-Culture).Name) / ANSI $([Text.Encoding]::Default.CodePage)"
        "CPU             : $("$($cpu.Name)".Trim())（$($cpu.NumberOfCores) 核 / $($cpu.NumberOfLogicalProcessors) 线程）"
        "BIOS 虚拟化     : $($cpu.VirtualizationFirmwareEnabled)（Hypervisor 运行时此项显示 False 属正常）"
        "Hypervisor      : $(if ($cs.HypervisorPresent) { '正在运行' } else { '未运行' })"
        "内存            : $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB"
        "系统盘剩余      : $($S.freeGB) GB"
        "显卡            : $gpu"
        "用户名含中文    : $(if ($env:USERNAME -match '[^\x00-\x7F]') { '是' } else { '否' })"
        "原 TEMP 目录    : $origTemp"
        if ($inst) { "本次安装 TEMP   : $runTemp（已自动改用纯英文路径）" }
        "待重启状态      : $(Get-PendingReboot)"
        "诊断器运行于    : $BAT"
    }

    Sec '安装包' {
        if (-not $inst) { '本次未运行安装程序（仅检测模式）'; return }
        $fi = Get-Item -LiteralPath $inst
        $vi = $fi.VersionInfo
        $S.instVerStr = $vi.ProductVersion
        if ("$($vi.ProductVersion)" -match '(\d+)\.(\d+)\.(\d+)') { $S.instVer = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
        Say '      计算安装包 SHA256……' 'DarkGray'
        $hash = (Get-FileHash -LiteralPath $inst -Algorithm SHA256).Hash
        $sig  = Get-AuthenticodeSignature -LiteralPath $inst
        $S.sigOK = ("$($sig.Status)" -eq 'Valid')
        "路径     : $inst"
        "大小     : $([math]::Round($fi.Length / 1MB, 1)) MB"
        "产品版本 : $($vi.ProductVersion)    文件版本 : $($vi.FileVersion)"
        "公司     : $($vi.CompanyName)"
        "SHA256   : $hash（可与 Broadcom 下载页公布的值比对）"
        "数字签名 : $($sig.Status)    签名者 : $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '无' })"
    }

    Sec '本次安装过程' {
        if (-not $inst) { '跳过'; return }
        "开始 : $($t0.ToString('yyyy-MM-dd HH:mm:ss'))    结束 : $($t1.ToString('HH:mm:ss'))    耗时 : $([int]($t1 - $t0).TotalSeconds) 秒"
        if ($S.startErr) { "安装程序无法启动 : $($S.startErr)" } else { "退出码 : $(Fmt-Exit $S.exit)" }
    }

    Sec '启动测试' { $S.launch }

    Sec '虚拟化 / Hyper-V / 内核隔离（VMware 最常见的冲突源）' {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -EA 0
        if ($dg) {
            $S.vbs = [int]$dg.VirtualizationBasedSecurityStatus
            $run = @($dg.SecurityServicesRunning)
            $S.hvciRun = ($run -contains 2)
            $svcName = @{ 0 = '无'; 1 = '凭据保护'; 2 = '内存完整性(HVCI)'; 3 = '系统防护'; 4 = 'SMM 防护'; 5 = '内核栈保护' }
            "基于虚拟化的安全 (VBS) : $(@('关闭', '已启用但未运行', '正在运行')[$S.vbs])"
            "运行中的安全服务       : $((@($run | ForEach-Object { $svcName[[int]$_] })) -join '，')"
        } else { '(无法读取 DeviceGuard 信息)' }
        $hv = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -EA 0).Enabled
        $S.hvciReg = ($hv -eq 1)
        "内存完整性开关         : $(if ($hv -eq 1) { '开启' } elseif ($null -eq $hv) { '未配置' } else { '关闭' })"
        $hl = @(& bcdedit /enum '{current}' 2>&1 | Select-String -Pattern 'hypervisorlaunchtype') | Select-Object -First 1
        $S.hvLaunch = if ($hl) { ("$hl".Trim() -split '\s+')[-1] } else { '未设置' }
        "hypervisorlaunchtype   : $($S.hvLaunch)"
        $names = 'Microsoft-Hyper-V-All', 'Microsoft-Hyper-V-Hypervisor', 'VirtualMachinePlatform', 'HypervisorPlatform',
                 'Containers-DisposableClientVM', 'Windows-Defender-ApplicationGuard', 'Microsoft-Windows-Subsystem-Linux'
        $q = 'SELECT Name,InstallState FROM Win32_OptionalFeature WHERE ' + ((@($names | ForEach-Object { "Name='$_'" })) -join ' OR ')
        $feat = @(Get-CimInstance -Query $q -EA 0)
        $S.hvFeatures = @($feat | Where-Object { $_.InstallState -eq 1 -and $_.Name -ne 'Microsoft-Windows-Subsystem-Linux' } | ForEach-Object { $_.Name })
        'Windows 可选功能：'
        foreach ($f in ($feat | Sort-Object Name)) { '  {0,-40} {1}' -f $f.Name, $(if ($f.InstallState -eq 1) { '已启用' } else { '未启用' }) }
    }

    Sec '安全软件（拦截 VMware 内核驱动的头号嫌疑）' {
        $av = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -EA 0)
        '安全中心登记的杀毒软件：'
        if ($av.Count) { foreach ($a in $av) { "  $($a.displayName)    状态码 $($a.productState)" } } else { '  (无 / 无法读取)' }
        $S.avReg = @($av | Where-Object { $_.displayName -notmatch '(?i)Windows Defender|Microsoft Defender' } | ForEach-Object { $_.displayName })
        $avMap = [ordered]@{
            '360tray' = '360安全卫士'; '360sd' = '360杀毒'; 'ZhuDongFangYu' = '360主动防御'; '360rp' = '360杀毒实时防护'
            'HipsTray' = '火绒'; 'HipsDaemon' = '火绒'; 'usysdiag' = '火绒'
            'QQPCTray' = '腾讯电脑管家'; 'QQPCRTP' = '腾讯电脑管家实时防护'
            'kxetray' = '金山毒霸'; 'kxescore' = '金山毒霸'; 'KSafeTray' = '金山卫士'
            '2345SafeTray' = '2345安全卫士'; '2345RTProtect' = '2345安全卫士'
            'avp' = '卡巴斯基'; 'ekrn' = 'ESET'; 'AvastSvc' = 'Avast'; 'AVGSvc' = 'AVG'; 'mcshield' = 'McAfee'
            'bdservicehost' = 'Bitdefender'; 'ccSvcHst' = 'Norton'; 'NortonSecurity' = 'Norton'; 'SavService' = 'Sophos'
        }
        $running = @(Get-Process -EA 0 | ForEach-Object { $_.ProcessName } | Select-Object -Unique)
        $S.av = @(foreach ($k in $avMap.Keys) { if ($running -contains $k) { "$($avMap[$k])($k.exe)" } })
        '正在运行的第三方安全软件进程：'
        if ($S.av.Count) { foreach ($x in $S.av) { "  $x" } } else { '  (未发现常见安全软件进程)' }
    }

    Sec 'VMware 安装前残留快照（运行安装程序之前）' {
        '已登记安装的 VMware 产品：'; Tbl $pre.Uninst
        'VMware 服务 / 驱动：';       Tbl $pre.Svc
        'VMware 目录：';              Tbl $pre.Dirs
        '运行中的 VMware 进程：';     Tbl $pre.Proc
    }

    Sec 'VMware 当前状态（安装程序结束后）' {
        '已登记安装的 VMware 产品：'; Tbl (Get-Uninst 'VMware')
        'VMware 服务 / 驱动：';       Tbl (Get-VMSvc)
        'VMware 目录：';              Tbl (Get-VMDirs)
        'VMware 虚拟网卡：'
        Tbl @(Get-NetAdapter -IncludeHidden -EA 0 | Where-Object { $_.InterfaceDescription -match 'VMware' } | Select-Object Name, InterfaceDescription, Status)
        '驱动库中的 VMware 驱动包：'
        Say '      扫描驱动库……' 'DarkGray'
        Tbl @(Get-WindowsDriver -Online -EA 0 | Where-Object { $_.ProviderName -match 'VMware' } |
              Select-Object Driver, ClassName, Version, Date, @{ n = '原始文件'; e = { Split-Path $_.OriginalFileName -Leaf } })
    }

    Sec '运行库与系统组件' {
        'VC++ 运行库：'
        $vc = Get-Uninst 'Visual C\+\+ (2015|2017|2019|2022)'
        if ($vc.Count) { Tbl ($vc | Select-Object DisplayName, DisplayVersion | Sort-Object DisplayName) } else { '  (未找到 VC++ 2015-2022 运行库！)'; $S.noVC = $true }
        '关键运行库文件：'
        foreach ($d in "$env:WINDIR\System32", "$env:WINDIR\SysWOW64") {
            foreach ($f in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'ucrtbase.dll') {
                $fp = Join-Path $d $f
                if (Test-Path -LiteralPath $fp) { '  {0,-48} {1}' -f $fp, (Get-Item -LiteralPath $fp).VersionInfo.FileVersion }
                elseif ($f -ne 'vcruntime140_1.dll' -or $d -like '*System32') { '  {0,-48} 缺失！' -f $fp; $S.vcMissing = $true }
            }
        }
        $msi = Get-Service msiserver -EA 0
        $S.msiDisabled = ("$($msi.StartType)" -eq 'Disabled')
        "Windows Installer 服务 : $($msi.Status) / 启动类型 $($msi.StartType)"
        ".NET Framework 4 Release : $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -EA 0).Release)"
    }

    Sec "本次运行期间的事件日志（$($tE.ToString('yyyy-MM-dd HH:mm:ss')) 之后）" {
        $app = Get-Ev @{ LogName = 'Application'; Id = 1000, 1001, 1002, 1026; StartTime = $tE } 40
        $S.faults = @(foreach ($e in @($app | Where-Object { $_.Id -eq 1000 })) {
                [pscustomobject]@{ App = $e.Properties[0].Value; Module = $e.Properties[3].Value; Code = $e.Properties[6].Value; Path = "$($e.Properties[10].Value)" } })
        $S.vmFaults = @($S.faults | Where-Object { $_.App -match '(?i)vmware|vmplayer|vmx|msiexec|setup' -or $_.Path -like "$runTemp*" })
        "应用程序崩溃 / 挂起 / .NET 异常：$($app.Count) 条"
        foreach ($e in $app) { Fmt-Ev $e }
        $msiEv = Get-Ev @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; StartTime = $tE } 40
        "Windows Installer 事件：$($msiEv.Count) 条"
        foreach ($e in $msiEv) { Fmt-Ev $e 800 }
        $sxs = Get-Ev @{ LogName = 'Application'; ProviderName = 'SideBySide'; Level = 2; StartTime = $tE } 10
        if ($sxs.Count) { $S.sxs = $true; 'SideBySide 并行配置错误（运行库清单问题）：'; foreach ($e in $sxs) { Fmt-Ev $e } }
        $sys = @(Get-Ev @{ LogName = 'System'; Level = 1, 2, 3; StartTime = $tE } 80 | Where-Object {
                $_.ProviderName -match 'Service Control Manager|Kernel-PnP|UserPnp|DriverFrameworks' -or $_.Message -match '(?i)vmware|vmx86|vmci|hcmon|vmnet|vmusb' })
        $S.scmVM = @($sys | Where-Object { $_.Message -match '(?i)vmware|vmx86|vmci|hcmon|vmnet|vmusb|VMAuthd|VMUSBArb' })
        "系统日志中驱动 / 服务相关错误：$($sys.Count) 条"
        foreach ($e in @($sys | Select-Object -First 25)) { Fmt-Ev $e 600 }
        $ci = Get-Ev @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; Level = 1, 2, 3; StartTime = $tE } 40
        $S.ciVM = @($ci | Where-Object { $_.Message -match '(?i)vmware|vmx86|vmci|hcmon|vmnet|vmusb' })
        "代码完整性（驱动签名 / 内存完整性拦截）：$($ci.Count) 条，其中涉及 VMware：$($S.ciVM.Count) 条"
        foreach ($e in @($ci | Select-Object -First 15)) { Fmt-Ev $e 600 }
    }

    Sec '历史崩溃与安装失败记录（近 30 天，本次运行之前）' {
        $since = (Get-Date).AddDays(-30)
        $h = @(Get-Ev @{ LogName = 'Application'; Id = 1000, 1001; StartTime = $since } 500 |
               Where-Object { $_.TimeCreated -lt $tE -and $_.Message -match '(?i)vmware|vmplayer|vmx|vmnet|vmauthd' } | Select-Object -First 10)
        $S.histFaults = @($h | Where-Object { $_.Id -eq 1000 } | ForEach-Object {
                [pscustomobject]@{ App = $_.Properties[0].Value; Module = $_.Properties[3].Value; Code = $_.Properties[6].Value } })
        "VMware 相关崩溃：$($h.Count) 条"
        foreach ($e in $h) { Fmt-Ev $e 1200 }
        $hm = @(Get-Ev @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; StartTime = $since } 400 |
                Where-Object { $_.TimeCreated -lt $tE -and $_.Message -match 'VMware' } | Select-Object -First 12)
        "VMware 相关 Windows Installer 事件：$($hm.Count) 条"
        foreach ($e in $hm) { Fmt-Ev $e 600 }
        $hc = @(Get-Ev @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; Level = 1, 2, 3; StartTime = $since } 500 |
                Where-Object { $_.TimeCreated -lt $tE -and $_.Message -match '(?i)vmware|vmx86|vmci|hcmon|vmnet|vmusb' } | Select-Object -First 8)
        if ($hc.Count) { $S.ciVMHist = $true; "代码完整性拦截 VMware 驱动：$($hc.Count) 条"; foreach ($e in $hc) { Fmt-Ev $e 600 } }
    }

    Sec 'Windows 错误报告 (WER)：崩溃现场加载的非系统模块（可揪出注入的第三方 DLL）' {
        $roots = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
                 "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive", "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"
        $since = (Get-Date).AddDays(-30)
        $dirs = @(@(foreach ($r in $roots) { Get-ChildItem -LiteralPath $r -Directory -EA 0 |
                    Where-Object { $_.Name -match '(?i)vmware|vmplayer|vmx|vmnet' -and $_.LastWriteTime -gt $since } }) |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 4)
        if (-not $dirs.Count) { '(近 30 天无 VMware 相关 WER 报告)'; return }
        $S.werMods = @()
        foreach ($d in $dirs) {
            $f = Join-Path $d.FullName 'Report.wer'
            if (-not (Test-Path -LiteralPath $f)) { continue }
            Copy-Shared $f (Join-Path $rawDir ('WER_' + $d.Name + '.wer'))
            $L = @(Get-Content -LiteralPath $f -EA 0)
            "--- $($d.Name)（$($d.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))）---"
            foreach ($x in @($L | Where-Object { $_ -match '^(EventType|FriendlyEventName|AppName|AppPath|Sig\[\d+\]\.(Name|Value))=' })) { "  $x" }
            $mods = @($L | Where-Object { $_ -match '^LoadedModule\[\d+\]=' } | ForEach-Object { ($_ -split '=', 2)[1] } |
                      Where-Object { $_ -notmatch '^(?i)[A-Z]:\\Windows\\' })
            "  非系统目录模块（$($mods.Count) 个）："
            foreach ($x in $mods) { "    $x" }
            $S.werMods += $mods
        }
    }

    Sec '安装日志摘录' {
        $logs = New-Object System.Collections.Generic.List[object]
        if (Test-Path -LiteralPath $runTemp) {
            Get-ChildItem -LiteralPath $runTemp -Recurse -File -EA 0 | Where-Object { $_.Name -match '(?i)\.log|vminst|vmmsi' -and $_.Length -lt 200MB } |
                ForEach-Object { $logs.Add(@{ F = $_; Tag = '本次' }) }
        }
        Get-ChildItem -LiteralPath "$env:WINDIR\Temp" -File -EA 0 | Where-Object { $_.Name -match '^(?i)MSI.*\.LOG$' -and $_.LastWriteTime -gt $tE } |
            ForEach-Object { $logs.Add(@{ F = $_; Tag = '本次（系统端 MSI）' }) }
        Get-ChildItem -LiteralPath $origTemp -File -EA 0 | Where-Object { $_.Name -match '^(?i)(vminst|vmmsi)' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { $logs.Add(@{ F = $_; Tag = '历史（你之前几次安装留下的）' }) }
        if ($logs.Count -eq 0) {
            $S.noLogs = $true
            '(未找到任何安装日志：安装程序可能在写日志之前就已崩溃，请重点看事件日志与 WER 部分)'
            return
        }
        $n = 0
        foreach ($x in $logs) {
            $fi = $x.F; $n++
            Copy-Shared $fi.FullName (Join-Path $rawDir ("{0:D2}_{1}" -f $n, $fi.Name))
            if ($n -gt 6) { continue }          # 报告里最多摘 6 份，其余只进压缩包
            "##### [$($x.Tag)] $($fi.FullName)    $([math]::Round($fi.Length / 1KB)) KB    修改于 $($fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            $txt = Read-Shared $fi.FullName
            if ($txt -match 'Return value 3') { $S.msiRV3 = $true }
            Excerpt $txt
            ''
        }
    }

    Sec 'VMware 程序日志（打开就闪退时看这里）' {
        $c = @()
        $c += @(Get-ChildItem -LiteralPath $origTemp -Directory -EA 0 | Where-Object { $_.Name -like 'vmware-*' } |
                ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File -Filter '*.log' -EA 0 })
        $c += @(Get-ChildItem -LiteralPath "$env:ProgramData\VMware\logs" -File -EA 0)
        $c = @($c | Where-Object { $_ -and $_.LastWriteTime -gt (Get-Date).AddDays(-7) } | Sort-Object LastWriteTime -Descending | Select-Object -First 3)
        if (-not $c.Count) { '(近 7 天无 VMware 程序日志)'; return }
        foreach ($fi in $c) {
            Copy-Shared $fi.FullName (Join-Path $rawDir ('VMLOG_' + $fi.Name))
            "##### $($fi.FullName)    修改于 $($fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            $L = (Read-Shared $fi.FullName) -split '\r?\n'
            $err = @($L | Where-Object { $_ -match '(?i)panic|error|fail|exception|unexpected|assert|backtrace|crash' } | Select-Object -Last 25)
            if ($err.Count) { '--- 关键词行 ---'; foreach ($x in $err) { Cut $x } }
            '--- 结尾 25 行 ---'; foreach ($x in @($L | Select-Object -Last 25)) { Cut $x }
            ''
        }
    }

    # ---------- 自动初判 ----------
    if ($inst) {
        if ($S.startErr)             { Hint "安装程序根本无法启动：$($S.startErr) → 多为安全软件拦截或安装包损坏。" }
        elseif ($S.exitCrash)        { Hint "安装程序异常崩溃，退出码 $(Fmt-Exit $S.exit)。" }
        elseif ($S.exit -eq 1603)    { Hint '安装程序报 1603 致命错误 → 典型原因：旧版残留 / 安全软件拦截驱动 / 驱动加载失败；见「安装日志摘录」中 Return value 3 之前的内容。' }
        elseif ($S.exit -eq 1618)    { Hint '另一个安装程序正在运行（1618）→ 等它结束或重启电脑后再试。' }
        elseif ($S.exit -eq 0 -or $S.exit -eq 3010) { Hint "安装程序正常结束（退出码 $($S.exit)）。如果你遇到的是「打开就闪退」，看启动测试结果。" }
        elseif ($null -ne $S.exit)   { Hint "安装程序非正常退出，退出码 $(Fmt-Exit $S.exit)。" }
    }
    foreach ($f in @($S.vmFaults | Select-Object -First 3)) { Hint (Diagnose-Module $f.App $f.Module $f.Code) }
    if (-not $S.vmFaults.Count -and $S.histFaults.Count) {
        foreach ($f in @($S.histFaults | Select-Object -First 2)) { Hint ('[历史] ' + (Diagnose-Module $f.App $f.Module $f.Code)) }
    }
    if ($S.launchBad) { Hint "启动测试：$($S.launch)" }
    if ($S.vbs -eq 2 -or $S.hvciRun -or $S.hvciReg) {
        Hint '基于虚拟化的安全 / 内存完整性正在运行 → 与 VMware 冲突的高发项。处理：Windows 安全中心 → 设备安全性 → 内核隔离 → 关闭「内存完整性」，重启。'
    }
    if ($S.hvLaunch -match '^(?i)(auto|on)$' -or $S.hvFeatures.Count) {
        Hint "Hyper-V 系 Hypervisor 已启用（hypervisorlaunchtype=$($S.hvLaunch)；已启用功能：$(if ($S.hvFeatures.Count) { $S.hvFeatures -join '、' } else { '无' })）→ 若不依赖 WSL2 / Docker / 安卓模拟器，管理员执行 bcdedit /set hypervisorlaunchtype off 后重启。"
    }
    if ($S.ciVM.Count -or $S.ciVMHist) { Hint '代码完整性日志显示 VMware 驱动被拦截 → 内存完整性 / 驱动阻止列表所致，关闭内存完整性后重试。' }
    $avAll = @(@($S.av) + @($S.avReg) | Where-Object { $_ } | Select-Object -Unique)
    if ($avAll.Count) { Hint "检测到第三方安全软件：$($avAll -join '、') → 会拦截 VMware 内核驱动（vmx86 / vmnet）。安装前从托盘彻底退出，不只是关实时防护。" }
    if ($S.preResidue) { Hint '安装前存在 VMware 服务 / 驱动 / 目录残留，但系统里没有登记的已安装产品 → 典型的多次安装失败残留，需要先彻底清理（见「安装前残留快照」）。' }
    elseif ($S.preInstalled) { Hint "安装前系统里已登记安装：$((@($pre.Uninst | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" })) -join '；') → 新安装程序会走升级 / 修复流程，建议先卸载再清残留。" }
    if ($S.scmVM.Count) { Hint 'VMware 服务 / 驱动启动失败（系统日志）→ 多为旧驱动残留或安全软件拦截。' }
    if ($inst -and $S.sigOK -eq $false) { Hint '安装包数字签名无效 → 下载损坏或被篡改，请从 Broadcom 官网重新下载。' }
    if ($S.nonAsciiUser) { Hint '用户名 / TEMP 路径含中文 → 本次已自动改用 C:\VMDiag_Temp 规避；如果本次能装上而平时失败，原因就是它。' }
    if ($S.noLogs -and $inst) { Hint '没有生成任何安装日志 → 安装程序在初始化阶段就崩溃，重点怀疑安全软件拦截 / 第三方注入 / 安装包损坏。' }
    if ($S.vcMissing -or $S.noVC) { Hint 'VC++ 运行库文件缺失 → 安装 VC++ 2015-2022 的 x64 与 x86 两个版本。' }
    if ($S.sxs) { Hint '出现 SideBySide 并行配置错误 → VC++ 运行库损坏，修复 VC++ 2015-2022。' }
    if ($S.msiDisabled) { Hint 'Windows Installer 服务被禁用 → services.msc 里把它改成「手动」。' }
    if ($S.pendingReboot) { Hint '系统有未完成的更新重启 → 先重启电脑再安装。' }
    if ($S.freeGB -and $S.freeGB -lt 10) { Hint "系统盘只剩 $($S.freeGB) GB → 空间不足，至少留 10 GB。" }
    if ($S.build -and $S.build -lt 17763) { Hint "系统版本过旧（内部版本 $($S.build)）→ VMware 17 需要较新的 Windows 10 / 11。" }
    if ($S.build -ge 26100 -and $S.instVer -and $S.instVer -lt [version]'17.6.0') { Hint "Windows 11 24H2 及以上 + VMware $($S.instVerStr) 过旧 → 改用 17.6.x 或更新版本。" }
    if ($S.werMods.Count) {
        $third = @($S.werMods | Where-Object { $_ -notmatch '(?i)\\VMware\\|VMDiag_Temp' -and $_ -ne $inst -and $_ -notmatch '(?i)\\VMware-(workstation|player)' } | Select-Object -Unique)
        if ($third.Count) { Hint "崩溃现场加载了这些第三方模块：$($third -join '；') → 逐个排查（输入法 / 安全软件 / 加速器 / 录屏等注入）。" }
    }
    if ($Hints.Count -eq 0) { Hint '没有命中已知规则，请把完整报告发给 Claude 人工分析。' }

    # ---------- 出报告 ----------
    $hd = New-Object System.Text.StringBuilder
    [void]$hd.AppendLine("VMware 安装诊断报告    诊断器 $VER    生成于 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$hd.AppendLine('把本文件发给 Claude 即可（已复制到剪贴板，回到对话框 Ctrl+V；或直接把本文件拖进对话框）。')
    [void]$hd.AppendLine('')
    [void]$hd.AppendLine('【自动初判】（规则匹配出的嫌疑项，供参考，不是最终结论）')
    $i = 1; foreach ($h in $Hints) { [void]$hd.AppendLine("  $i. $h"); $i++ }
    $report = $hd.ToString() + $RB.ToString()
    $repPath = Join-Path $outDir '诊断报告.txt'
    [IO.File]::WriteAllText($repPath, $report, (New-Object Text.UTF8Encoding $true))
    $zip = "$outDir.zip"
    try { Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip -Force -ErrorAction Stop } catch { $zip = $null }
    $clip = $false
    try { Set-Clipboard -Value $report -ErrorAction Stop; $clip = $true } catch {}
    if ($S.exit -ne 3010) { Remove-Item -LiteralPath $runTemp -Recurse -Force -EA 0 }   # 清理本次临时目录（需重启的情况保留）

    Say ''
    Say '  ==============  诊断完成  ==============' 'Green'
    Say '  【自动初判】' 'Yellow'
    $i = 1; foreach ($h in $Hints) { Say "  $i. $h" 'Yellow'; $i++ }
    Say ''
    Say "  报告文件 : $repPath" 'White'
    if ($zip) { Say "  完整压缩包 : $zip（含原始日志）" 'White' }
    if ($clip) { Say '  报告全文已复制到剪贴板 → 回到 Claude 对话框直接 Ctrl+V 发送。' 'Green' }
    else { Say '  剪贴板复制失败 → 请把上面的「诊断报告.txt」拖进 Claude 对话框。' 'Yellow' }
    try { Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList ('/select,"' + $repPath + '"') } catch {}
} catch {
    Say "诊断器内部错误：$($_.Exception.Message)" 'Red'
    Say "位置：$($_.InvocationInfo.PositionMessage)" 'Red'
    try { Restore-MsiLogging; if ($origTemp) { $env:TEMP = $origTemp; $env:TMP = $origTmp } } catch {}
}
Say ''
Read-Host '按回车键关闭本窗口' | Out-Null
