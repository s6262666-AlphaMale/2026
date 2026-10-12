@echo off
chcp 936 >nul
title VMware 残留清理器 v1.0
rem ===========================================================================
rem  VMware 残留清理器 v1.0
rem  用途：清除 VMware Workstation / Player 多次安装失败留下的残留，
rem        重点修复「安装程序 7 秒退出、退出码 1608」：
rem        Windows Installer 里残留半注册的旧版本（常见于改版/游戏多开版 VMware 卸载失败）。
rem  安全：先只读扫描并列出清单，你输入 Y 才动手；
rem        注册表项全部 reg export 备份，目录与驱动文件只改名不删除，并自动生成「还原.bat」。
rem  备份位置：H:\Claude Code MCP\VMware清理备份_时间戳\（该盘不存在则放在本 bat 旁边）
rem  本文件编码：GBK + CRLF，请勿用记事本另存为 UTF-8。
rem ===========================================================================
set "VMCLEAN_BAT=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$m='::'+'PS_START'; $s=[IO.File]::ReadAllText($env:VMCLEAN_BAT,[Text.Encoding]::GetEncoding(936)); iex ($s.Substring($s.IndexOf($m)+$m.Length))"
exit /b
::PS_START
# ============================================================================
#  以下为 PowerShell 代码，由上方 bat 读取执行（cmd 执行到 exit /b 就结束，不会解析到这里）
#  流程：提权 → 只读扫描 → 列清单 → 输入 Y 确认 → 备份 → 清理 → 生成还原.bat → 提示重启
# ============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$VER   = 'v1.0'
$BAT   = $env:VMCLEAN_BAT
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
try { $Host.UI.RawUI.WindowTitle = "VMware 残留清理器 $VER" } catch {}
function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }

# ---------- 0. 管理员权限：不足则自动提权，在新窗口重开 ----------
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Say '需要管理员权限，正在请求提权，请在弹窗中点「是」……' 'Yellow'
    $lit  = "'" + ($BAT -replace "'", "''") + "'"
    $boot = "`$env:VMCLEAN_BAT=$lit; `$m='::'+'PS_START'; `$s=[IO.File]::ReadAllText(`$env:VMCLEAN_BAT,[Text.Encoding]::GetEncoding(936)); iex (`$s.Substring(`$s.IndexOf(`$m)+`$m.Length))"
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
$LOG = New-Object System.Text.StringBuilder
function Log([string]$t, [string]$c = 'Gray') { Say $t $c; [void]$LOG.AppendLine($t) }
# MSI 压缩 GUID 与标准 GUID 互转（该变换自身互逆）
function Pack-Guid([string]$g) {
    $h = ($g -replace '[{}\-]', '').ToUpper()
    if ($h -notmatch '^[0-9A-F]{32}$') { return $null }
    $a = $h.Substring(0, 8).ToCharArray();  [array]::Reverse($a); $r = -join $a
    $a = $h.Substring(8, 4).ToCharArray();  [array]::Reverse($a); $r += -join $a
    $a = $h.Substring(12, 4).ToCharArray(); [array]::Reverse($a); $r += -join $a
    for ($i = 16; $i -lt 32; $i += 2) { $r += [string]$h[$i + 1] + [string]$h[$i] }
    $r
}
function Unpack-Guid([string]$p) {
    $h = Pack-Guid $p
    if (-not $h) { return $null }
    '{' + $h.Substring(0, 8) + '-' + $h.Substring(8, 4) + '-' + $h.Substring(12, 4) + '-' + $h.Substring(16, 4) + '-' + $h.Substring(20, 12) + '}'
}
# PowerShell 注册表路径 → reg.exe 可用的原生路径
function NativeKey([string]$p) {
    $p -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
}
# 服务 ImagePath → 实际文件路径
function Resolve-Image([string]$ip) {
    if (-not $ip) { return $null }
    $p = $ip.Trim()
    if ($p.StartsWith('"')) { $e = $p.IndexOf('"', 1); if ($e -gt 1) { $p = $p.Substring(1, $e - 1) } }
    elseif ($p -match '^(.*?\.(exe|sys))') { $p = $Matches[1] }
    $p = $p -replace '^\\\?\?\\', ''
    $p = $p -replace '^(?i)\\SystemRoot\\', "$env:SystemRoot\"
    $p = $p -replace '^(?i)system32\\', "$env:SystemRoot\System32\"
    $p
}

try {
    # ---------- 输出 / 备份目录 ----------
    $batDir  = [IO.Path]::GetDirectoryName($BAT)
    $outBase = $null
    foreach ($d in @('H:\Claude Code MCP', $batDir, [Environment]::GetFolderPath('Desktop'))) {
        if ($d -and (Test-Path -LiteralPath $d)) {
            try { $pr = Join-Path $d ".vmclean_probe_$stamp"; [IO.File]::WriteAllText($pr, 'x'); Remove-Item -LiteralPath $pr -Force; $outBase = $d; break } catch {}
        }
    }
    if (-not $outBase) { $outBase = $env:SystemDrive + '\' }
    $bkDir = Join-Path $outBase "VMware清理备份_$stamp"
    $sfx   = ".vmbak_$stamp"                     # 改名后缀（纯英文，系统目录里更安全）

    Say ''
    Say "  ==============  VMware 残留清理器 $VER  ==============" 'Cyan'
    Say '  第一步只扫描、不改动任何东西。' 'DarkYellow'
    Say ''
    Say '[1/4] 扫描残留……' 'Cyan'

    # ---------- A. 安装日志里报 1608 的产品代码 ----------
    $logDirs = @($env:TEMP)
    $deepDirs = @((Join-Path $env:SystemDrive 'VMDiag_Temp'))
    foreach ($b in @('H:\Claude Code MCP', $batDir)) {
        if ($b -and (Test-Path -LiteralPath $b)) { $deepDirs += @(Get-ChildItem -LiteralPath $b -Directory -Filter 'VMware诊断_*' -EA 0 | ForEach-Object { $_.FullName }) }
    }
    $logFiles = @()
    foreach ($d in $logDirs)  { $logFiles += @(Get-ChildItem -LiteralPath $d -File -EA 0 | Where-Object { $_.Name -match '(?i)vminst' }) }
    foreach ($d in $deepDirs) { if (Test-Path -LiteralPath $d) { $logFiles += @(Get-ChildItem -LiteralPath $d -Recurse -File -EA 0 | Where-Object { $_.Name -match '(?i)vminst' }) } }
    $logGuids = @(@(foreach ($f in $logFiles) {
            Select-String -LiteralPath $f.FullName -Pattern 'installed product (\{[0-9A-Fa-f\-]{36}\})' -EA 0 | ForEach-Object { $_.Matches[0].Groups[1].Value.ToUpper() }
        }) | Select-Object -Unique)
    $logPacked = @($logGuids | ForEach-Object { Pack-Guid $_ } | Where-Object { $_ })

    # ---------- B. 是否装有其他 VMware 产品（Horizon / Remote Console 等），有则收窄清理范围 ----------
    $uninstRoots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                     'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    $otherVM = @(@(foreach ($u in $uninstRoots) {
            Get-ChildItem -LiteralPath $u -EA 0 | ForEach-Object { "$((Get-ItemProperty -LiteralPath $_.PSPath -EA 0).DisplayName)" } |
                Where-Object { $_ -match 'VMware' -and $_ -notmatch '(?i)Workstation|Player' }
        }) | Select-Object -Unique)
    $narrow = ($otherVM.Count -gt 0)

    # ---------- C. Windows Installer 内部登记（1608 的病根）----------
    $mgd = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Managed' -EA 0)
    $prodRoots = @('HKLM:\SOFTWARE\Classes\Installer\Products', 'HKCU:\Software\Microsoft\Installer\Products') + @($mgd | ForEach-Object { "$($_.PSPath)\Installer\Products" })
    $Products = @(foreach ($r in $prodRoots) {
            Get-ChildItem -LiteralPath $r -EA 0 | ForEach-Object {
                $pn = "$((Get-ItemProperty -LiteralPath $_.PSPath -EA 0).ProductName)"
                if ($pn -match '(?i)VMware (Workstation|Player)' -or $logPacked -contains $_.PSChildName) {
                    [pscustomobject]@{ Packed = $_.PSChildName.ToUpper(); Guid = (Unpack-Guid $_.PSChildName); Name = $pn }
                }
            }
        })
    $packedSet = @(@($Products | ForEach-Object { $_.Packed }) + $logPacked | Where-Object { $_ } | Select-Object -Unique)

    $Keys = New-Object System.Collections.Generic.List[object]          # 整键删除
    function AddKey([string]$p, [string]$why) {
        if ((Test-Path -LiteralPath $p) -and -not ($Keys | Where-Object { $_.Path -eq $p })) { $Keys.Add([pscustomobject]@{ Path = $p; Why = $why }) }
    }
    $userData = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData' -EA 0)
    foreach ($pk in $packedSet) {
        $g = Unpack-Guid $pk
        AddKey "HKLM:\SOFTWARE\Classes\Installer\Products\$pk" "MSI 产品登记 $g"
        AddKey "HKLM:\SOFTWARE\Classes\Installer\Features\$pk" "MSI 功能登记 $g"
        AddKey "HKCU:\Software\Microsoft\Installer\Products\$pk" "MSI 产品登记(当前用户) $g"
        AddKey "HKCU:\Software\Microsoft\Installer\Features\$pk" "MSI 功能登记(当前用户) $g"
        foreach ($ud in $userData) { AddKey "$($ud.PSPath)\Products\$pk" "MSI 安装数据 $g（$($ud.PSChildName)）" }
        foreach ($m in $mgd) {
            AddKey "$($m.PSPath)\Installer\Products\$pk" "MSI 托管产品登记 $g"
            AddKey "$($m.PSPath)\Installer\Features\$pk" "MSI 托管功能登记 $g"
        }
        foreach ($u in $uninstRoots) { AddKey "$u\$g" "卸载项 $g" }
    }
    # 名称为 VMware Workstation / Player 的卸载项
    foreach ($u in $uninstRoots) {
        Get-ChildItem -LiteralPath $u -EA 0 | ForEach-Object {
            $dn = "$((Get-ItemProperty -LiteralPath $_.PSPath -EA 0).DisplayName)"
            if ($dn -match '(?i)VMware (Workstation|Player)') { AddKey $_.PSPath "卸载项 $dn" }
        }
    }
    # 厂商配置键
    $vendorRoots = @('HKLM:\SOFTWARE\VMware, Inc.', 'HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.', 'HKCU:\Software\VMware, Inc.')
    if ($narrow) {
        foreach ($vr in $vendorRoots) { foreach ($sub in 'VMware Workstation', 'VMware Player', 'VMnetLib', 'VMware VMX') { AddKey "$vr\$sub" "VMware 配置（$sub）" } }
    } else {
        foreach ($vr in $vendorRoots) { AddKey $vr 'VMware 厂商配置' }
    }

    # 升级代码里对这些产品的引用（只删单个值）
    $Vals = New-Object System.Collections.Generic.List[object]
    foreach ($ur in 'HKLM:\SOFTWARE\Classes\Installer\UpgradeCodes', 'HKCU:\Software\Microsoft\Installer\UpgradeCodes',
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes') {
        foreach ($k in @(Get-ChildItem -LiteralPath $ur -EA 0)) {
            $names = @($k.GetValueNames())
            foreach ($pk in $packedSet) {
                if ($names -contains $pk) { $Vals.Add([pscustomobject]@{ Key = $k.PSPath; Native = $k.Name; Name = $pk; Why = "升级代码 $($k.PSChildName) → $(Unpack-Guid $pk)" }) }
            }
        }
    }

    # ---------- D. 服务 / 驱动（只认 VMware 专有服务名）----------
    $SvcNames = @('vmx86', 'hcmon', 'vmci', 'VMnetAdapter', 'VMnetBridge', 'VMnetuserif', 'vmusb', 'VMnetDHCP', 'VMware NAT Service',
                  'VMUSBArbService', 'VMAuthdService', 'VmwareAutostartService', 'VMwareHostd', 'vmkbd', 'VMparport')
    $Svcs = @(foreach ($n in $SvcNames) {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
            if (Test-Path -LiteralPath $k) {
                $ip = "$((Get-ItemProperty -LiteralPath $k -EA 0).ImagePath)"
                [pscustomobject]@{ Name = $n; Key = $k; ImagePath = $ip; File = (Resolve-Image $ip) }
            }
        })

    # ---------- E. 驱动包 ----------
    Say '      扫描驱动库（约 10~30 秒）……' 'DarkGray'
    $Pkgs = @(Get-WindowsDriver -Online -EA 0 | Where-Object {
            $_.ProviderName -match 'VMware' -or [IO.Path]::GetFileName("$($_.OriginalFileName)") -match '^(?i)(vmusb|vmci|vmx86|hcmon|vmkbd)\.inf$' } |
        Select-Object Driver, ClassName, ProviderName, Version, @{ n = 'Inf'; e = { [IO.Path]::GetFileName("$($_.OriginalFileName)") } })

    # ---------- F. 目录（改名备份）----------
    if ($narrow) {
        $dirCands = @("${env:ProgramFiles(x86)}\VMware\VMware Workstation", "${env:ProgramFiles(x86)}\VMware\VMware Player",
                      "$env:ProgramData\VMware\VMware Workstation", "$env:ProgramData\VMware\VMware Player", "$env:APPDATA\VMware")
    } else {
        $dirCands = @("${env:ProgramFiles(x86)}\VMware", "$env:ProgramFiles\VMware", "${env:CommonProgramFiles(x86)}\VMware",
                      "$env:CommonProgramFiles\VMware", "$env:ProgramData\VMware", "$env:APPDATA\VMware", "$env:LOCALAPPDATA\VMware")
    }
    $Dirs = @($dirCands | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)

    # ---------- G. 系统目录里的 VMware 驱动 / 服务程序文件（改名备份，防止旧版/改版文件版本相同不被覆盖）----------
    $fileCands = @($Svcs | ForEach-Object { $_.File })
    foreach ($f in 'vmx86', 'hcmon', 'vmci', 'vmnetadapter', 'vmnetbridge', 'vmnetuserif', 'vmusb', 'vmkbd') { $fileCands += "$env:SystemRoot\System32\drivers\$f.sys" }
    foreach ($f in 'vmnat', 'vmnetdhcp') { $fileCands += "$env:SystemRoot\System32\$f.exe"; $fileCands += "$env:SystemRoot\SysWOW64\$f.exe" }
    $Files = @($fileCands | Where-Object {
            $_ -and $_.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase) -and
            ([IO.Path]::GetFileName($_) -match '^(?i)(vm|hcmon)') -and (Test-Path -LiteralPath $_)
        } | Sort-Object -Unique)                                  # Sort-Object -Unique 不区分大小写：system32\DRIVERS 与 System32\drivers 视为同一文件

    # ---------- H. 进程 / 安全软件 ----------
    $Procs = @(Get-Process -EA 0 | Where-Object { $_.ProcessName -match '^(?i)(vmware.*|vmplayer|vmnat|vmnetdhcp|vmrun)$' })
    $avMap = [ordered]@{
        '360tray' = '360安全卫士'; '360sd' = '360杀毒'; 'ZhuDongFangYu' = '360主动防御'; 'HipsTray' = '火绒'; 'HipsDaemon' = '火绒'
        'QQPCTray' = '腾讯电脑管家'; 'QQPCRTP' = '腾讯电脑管家'; 'kxetray' = '金山毒霸'; 'kxescore' = '金山毒霸'; 'KSafeTray' = '金山卫士'
        '2345SafeTray' = '2345安全卫士'; '2345RTProtect' = '2345安全卫士'
    }

    # ---------- 2. 列清单 ----------
    $total = $Keys.Count + $Vals.Count + $Svcs.Count + $Pkgs.Count + $Dirs.Count + $Files.Count
    Say ''
    Log "[2/4] 扫描结果（共 $total 项）" 'Cyan'
    if ($narrow) { Log "  注意：检测到其他 VMware 产品（$($otherVM -join '、')），已自动收窄范围；清理后它们可能需要修复安装。" 'Yellow' }
    if ($logGuids.Count) { Log "  安装日志里报 1608 的产品代码：$($logGuids -join '，')" 'Yellow' }
    Log '  ● Windows Installer 半注册记录（1608 的病根）：' 'White'
    if ($Products.Count) { foreach ($p in $Products) { Log "      $($p.Guid)  $($p.Name)" } } else { Log '      (产品表中未找到；如有其他登记会在下面的注册表项中列出)' }
    Log "  ● 注册表项（先备份再删除）：$($Keys.Count) 个" 'White'
    foreach ($k in $Keys) { Log "      $(NativeKey $k.Path)    ← $($k.Why)" }
    Log "  ● 注册表值（先备份再删除）：$($Vals.Count) 个" 'White'
    foreach ($v in $Vals) { Log "      $($v.Native) : $($v.Name)    ← $($v.Why)" }
    Log "  ● 服务 / 驱动（禁用 → 停止 → 删除）：$($Svcs.Count) 个" 'White'
    foreach ($s in $Svcs) { Log "      $($s.Name)    $($s.ImagePath)" }
    Log "  ● 驱动包（pnputil 卸载，含 VMnet 虚拟网卡）：$($Pkgs.Count) 个" 'White'
    foreach ($p in $Pkgs) { Log "      $($p.Driver)  $($p.Inf)  $($p.ClassName)  $($p.ProviderName)  $($p.Version)" }
    Log "  ● 目录（改名为「原名$sfx」，不删除）：$($Dirs.Count) 个" 'White'
    foreach ($d in $Dirs) { Log "      $d" }
    Log "  ● 系统目录中的 VMware 驱动 / 程序文件（改名备份）：$($Files.Count) 个" 'White'
    foreach ($f in $Files) { Log "      $f" }
    if ($Procs.Count) { Log "  ● 将结束的 VMware 进程：$((@($Procs | ForEach-Object { $_.ProcessName }) | Select-Object -Unique) -join '、')" 'White' }
    Log '  不会动：你的虚拟机文件（.vmx/.vmdk，例如 E 盘的虚拟机目录）。' 'Green'

    if ($total -eq 0) {
        Log '  未发现任何 VMware 残留，无需清理。' 'Green'
    } else {
        # ---------- 安全软件必须先退出 ----------
        while ($true) {
            $running = @(Get-Process -EA 0 | ForEach-Object { $_.ProcessName } | Select-Object -Unique)
            $av = @(foreach ($k in $avMap.Keys) { if ($running -contains $k) { $avMap[$k] } }) | Select-Object -Unique
            if (-not $av) { break }
            Say ''
            Say "  检测到安全软件正在运行：$($av -join '、')。它会拦截删除驱动 / 服务。" 'Red'
            Say '  请从任务栏右下角托盘里右键它 →「退出」（不是关闭实时防护），然后回到这里。' 'Yellow'
            $a = Read-Host '  退出后直接按回车重新检测；输入 S 回车 = 不管它继续'
            if ($a -match '^(?i)s$') { Log "  用户选择在 $($av -join '、') 运行的情况下继续" 'Yellow'; break }
        }

        Say ''
        $ok = Read-Host '  确认按以上清单清理？输入 Y 回车开始（其他任意输入 = 取消，不做任何改动）'
        if ($ok -notmatch '^(?i)y$') {
            Log '  已取消，没有做任何改动。' 'Yellow'
        } else {
            New-Item -ItemType Directory -Path $bkDir -Force | Out-Null
            $restore = New-Object System.Collections.Generic.List[string]   # 还原.bat 的命令行
            $fail = 0
            $C = @{ n = 0 }
            function Backup-Key([string]$native) {
                $C.n++
                $safe = ($native -replace '[\\/:*?"<>|]', '_')
                if ($safe.Length -gt 120) { $safe = $safe.Substring($safe.Length - 120) }
                $file = Join-Path $bkDir ('{0:D3}_{1}.reg' -f $C.n, $safe)
                $null = & reg.exe export $native $file /y 2>&1
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $file)) { $restore.Add("reg import `"$file`""); return $true }
                return $false
            }

            Say ''
            Log '[3/4] 开始清理……' 'Cyan'

            # 1) 结束进程
            foreach ($p in $Procs) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; Log "  [进程] 已结束 $($p.ProcessName)" } catch { Log "  [进程] 无法结束 $($p.ProcessName)：$($_.Exception.Message)" 'Yellow' } }

            # 2) 驱动包（会同时移除 VMnet 虚拟网卡设备）
            foreach ($p in $Pkgs) {
                $out = & pnputil.exe /delete-driver $p.Driver /uninstall /force 2>&1
                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) { Log "  [驱动包] 已卸载 $($p.Driver)（$($p.Inf)）" 'Green' }
                else { $fail++; Log "  [驱动包] 卸载失败 $($p.Driver)（$($p.Inf)），返回码 $LASTEXITCODE：$(($out | Out-String).Trim())" 'Red' }
            }

            # 3) 服务 / 驱动：先备份 → 设为禁用（保证下次开机不再加载）→ 停止 → 删除
            foreach ($s in $Svcs) {
                if (-not (Test-Path -LiteralPath $s.Key)) { Log "  [服务] $($s.Name) 已随驱动包移除" 'Green'; continue }
                if (-not (Backup-Key (NativeKey $s.Key))) { $fail++; Log "  [服务] $($s.Name) 备份失败，为安全起见跳过" 'Red'; continue }
                $null = & sc.exe config $s.Name start= disabled 2>&1
                try { Set-ItemProperty -LiteralPath $s.Key -Name Start -Value 4 -Type DWord -ErrorAction Stop } catch {}
                $null = & sc.exe stop $s.Name 2>&1
                $null = & sc.exe delete $s.Name 2>&1
                if (-not (Test-Path -LiteralPath $s.Key)) { Log "  [服务] 已删除 $($s.Name)" 'Green' }
                else {
                    $st = (Get-ItemProperty -LiteralPath $s.Key -EA 0)
                    if ($st.DeleteFlag -eq 1) { Log "  [服务] $($s.Name) 已标记删除并禁用（重启后彻底消失）" 'Green' }
                    elseif ($st.Start -eq 4) { Log "  [服务] $($s.Name) 已禁用（删除未成功，重启后再运行一次本清理器即可）" 'Yellow' }
                    else { $fail++; Log "  [服务] $($s.Name) 禁用和删除都失败（可能被安全软件拦截）" 'Red' }
                }
            }

            # 4) 注册表项
            foreach ($k in $Keys) {
                if (-not (Test-Path -LiteralPath $k.Path)) { continue }
                $nk = NativeKey $k.Path
                if (-not (Backup-Key $nk)) { $fail++; Log "  [注册表] 备份失败，跳过：$nk" 'Red'; continue }
                try { Remove-Item -LiteralPath $k.Path -Recurse -Force -ErrorAction Stop; Log "  [注册表] 已删除 $nk" 'Green' }
                catch { $fail++; Log "  [注册表] 删除失败 $nk：$($_.Exception.Message)" 'Red' }
            }

            # 5) 注册表值（升级代码引用）
            foreach ($v in $Vals) {
                if (-not (Backup-Key $v.Native)) { $fail++; Log "  [注册表值] 备份失败，跳过：$($v.Native) : $($v.Name)" 'Red'; continue }
                try {
                    Remove-ItemProperty -LiteralPath $v.Key -Name $v.Name -ErrorAction Stop
                    Log "  [注册表值] 已删除 $($v.Native) : $($v.Name)" 'Green'
                    $kk = Get-Item -LiteralPath $v.Key -EA 0
                    if ($kk -and $kk.ValueCount -eq 0 -and $kk.SubKeyCount -eq 0) { Remove-Item -LiteralPath $v.Key -Force -EA 0 }
                } catch { $fail++; Log "  [注册表值] 删除失败 $($v.Native) : $($v.Name)：$($_.Exception.Message)" 'Red' }
            }

            # 6) 目录：改名备份
            foreach ($d in $Dirs) {
                $leaf = Split-Path $d -Leaf
                $new  = "$leaf$sfx"
                try {
                    Rename-Item -LiteralPath $d -NewName $new -ErrorAction Stop
                    $restore.Add("move `"$(Join-Path (Split-Path $d -Parent) $new)`" `"$d`"")
                    Log "  [目录] 已改名 $d → $new" 'Green'
                } catch { $fail++; Log "  [目录] 改名失败 $d（文件被占用？重启后再运行一次本清理器）：$($_.Exception.Message)" 'Red' }
            }

            # 7) 系统目录中的驱动 / 程序文件：仅当对应服务已删除或已禁用时才改名，绝不让开机找不到正在启用的驱动
            foreach ($f in $Files) {
                if (-not (Test-Path -LiteralPath $f)) { continue }
                $svc  = $Svcs | Where-Object { $_.File -and $_.File -ieq $f } | Select-Object -First 1
                $safe = $true
                if ($svc -and (Test-Path -LiteralPath $svc.Key)) { $safe = ((Get-ItemProperty -LiteralPath $svc.Key -EA 0).Start -eq 4) }
                foreach ($sn in $SvcNames) {
                    $sk = "HKLM:\SYSTEM\CurrentControlSet\Services\$sn"
                    if ((Test-Path -LiteralPath $sk) -and ((Resolve-Image "$((Get-ItemProperty -LiteralPath $sk -EA 0).ImagePath)") -ieq $f) -and
                        ((Get-ItemProperty -LiteralPath $sk -EA 0).Start -ne 4)) { $safe = $false }
                }
                if (-not $safe) { Log "  [文件] 跳过 $f（对应服务仍处于启用状态）" 'Yellow'; continue }
                $new = [IO.Path]::GetFileName($f) + $sfx
                try {
                    Rename-Item -LiteralPath $f -NewName $new -ErrorAction Stop
                    $restore.Add("move `"$(Join-Path (Split-Path $f -Parent) $new)`" `"$f`"")
                    Log "  [文件] 已改名 $f → $new" 'Green'
                } catch { Log "  [文件] 改名失败 $f（重启后再运行一次本清理器即可）：$($_.Exception.Message)" 'Yellow' }
            }

            # ---------- 生成还原.bat 与日志 ----------
            $rb = New-Object System.Text.StringBuilder
            [void]$rb.AppendLine('@echo off'); [void]$rb.AppendLine('chcp 936 >nul')
            [void]$rb.AppendLine("title 还原 VMware 清理（$stamp）")
            [void]$rb.AppendLine('rem 右键「以管理员身份运行」。按清理的逆序还原：先改回文件 / 目录名，再导回注册表。完成后重启电脑。')
            [void]$rb.AppendLine('fltmc >nul 2>&1 || (echo 请右键本文件，以管理员身份运行 & pause & exit /b)')
            for ($i = $restore.Count - 1; $i -ge 0; $i--) { [void]$rb.AppendLine($restore[$i]) }
            [void]$rb.AppendLine('echo 还原完成，请重启电脑。'); [void]$rb.AppendLine('pause')
            [IO.File]::WriteAllText((Join-Path $bkDir '还原.bat'), ($rb.ToString() -replace "`r?`n", "`r`n"), [Text.Encoding]::GetEncoding(936))

            Say ''
            if ($fail -eq 0) { Log '[4/4] 清理完成，全部成功。' 'Green' } else { Log "[4/4] 清理完成，有 $fail 项失败（见上方红字）。重启后再运行一次本清理器即可补清。" 'Yellow' }
            Log "  备份与还原脚本：$bkDir" 'White'
            Log ''
            Log '  接下来：' 'Cyan'
            Log '  1. 重启电脑（必须：卸掉仍在内存里的旧驱动，并完成系统待替换的文件）。' 'White'
            Log '  2. 重启后先从托盘彻底退出金山毒霸等安全软件。' 'White'
            Log '  3. 运行「VMware安装诊断器_v1.1.bat」，它会自动运行安装程序并再次采集结果。' 'White'
        }
    }

    New-Item -ItemType Directory -Path $bkDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $bkDir '清理日志.txt'), $LOG.ToString(), (New-Object Text.UTF8Encoding $true))
    try { Set-Clipboard -Value $LOG.ToString() -ErrorAction Stop; Say '  清理日志已复制到剪贴板，如有失败项可直接 Ctrl+V 发给 Claude。' 'Green' } catch {}

    if ($ok -match '^(?i)y$') {
        Say ''
        $yes = $false
        try { choice /c YN /m '  现在重启电脑吗？'; $yes = ($LASTEXITCODE -eq 1) } catch {}
        if ($yes) { & shutdown.exe /r /t 15 /c 'VMware 残留清理完成，15 秒后重启'; Say '  15 秒后重启；要取消请运行 shutdown /a' 'Yellow' }
    }
} catch {
    Say "清理器内部错误：$($_.Exception.Message)" 'Red'
    Say "位置：$($_.InvocationInfo.PositionMessage)" 'Red'
}
Say ''
Read-Host '按回车键关闭本窗口' | Out-Null
