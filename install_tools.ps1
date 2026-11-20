# ==========================================================
#  Root-Me tools: install (skips what is already installed)
#  + one folder per category with shortcuts
#
#  Run from a PowerShell window:
#    Set-ExecutionPolicy -Scope Process Bypass -Force
#    .\install_tools.ps1
#
#  You can run it as many times as you want: everything that is
#  already installed is detected and skipped.
# ==========================================================

# Options: change to $true if you want it (SageMath is very heavy, ~2 GB)
$InstallSage = $false

# Repair a broken PATH (system folders missing) for this session
foreach ($p in "$env:windir", "$env:windir\System32", "$env:windir\System32\Wbem", "$env:windir\System32\WindowsPowerShell\v1.0") {
    if (($env:Path -split ";") -notcontains $p) { $env:Path = "$env:Path;$p" }
}

# Relaunch as administrator if needed (WSL / VirtualBox / MSI installs)
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`""
    exit
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = "SilentlyContinue"   # the progress bar makes downloads much slower
    $Dossier = "$env:USERPROFILE\RootMe-Tools"
    $Tools   = "$Dossier\Tools"           # downloaded tools go here
    $Work    = "$Dossier\Workspace"        # drop challenge files here
    $Racine  = "$Dossier\Categories"       # category folders with shortcuts
    New-Item -ItemType Directory -Force -Path $Dossier, $Tools, $Work | Out-Null
    # Categories only holds shortcuts/links/.txt notes, never your tools or challenge files,
    # so it is safe to wipe and rebuild it fresh every run - this is what prevents old
    # shortcuts (from a previous version of this script) from piling up next to new ones.
    if (Test-Path $Racine) { Remove-Item $Racine -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $Racine | Out-Null
    Set-Location $Dossier

    # Only the Tools folder is excluded (PEASS, BeEF... are flagged as malware by Defender).
    # Workspace is NOT excluded: challenge files stay scanned.
    Write-Host "[configuration] Adding Windows Defender exclusion for the Tools folder..." -ForegroundColor Cyan
    Add-MpPreference -ExclusionPath $Tools -ErrorAction SilentlyContinue

    # Smart App Control (SAC) blocks unsigned installers (ExifTool, x64dbg, Cutter...).
    # It has no exclusion list, only On / Evaluation / Off, so the script only warns.
    # 0 = off, 1 = on (blocks), 2 = evaluation (does not block)
    $sacOn = $false
    $sacWasOn = $false
    try {
        $sac = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -ErrorAction Stop).VerifiedAndReputablePolicyState
        if ($sac -eq 1) { $sacOn = $true }
    } catch {}
    if ($sacOn) {
        Write-Host "[warning] Smart App Control is ON: unsigned installers will be blocked." -ForegroundColor Yellow
        Write-Host "          There is no exclusion for it. To let the script finish, open Windows Security," -ForegroundColor Yellow
        Write-Host "          App and browser control, Smart App Control settings, choose Off, then run the script again." -ForegroundColor Yellow
        Write-Host "          You can turn it back on afterwards on an up to date Windows 11." -ForegroundColor Yellow
        $sacWasOn = $true
        Start-Process "windowsdefender://appbrowser" -ErrorAction SilentlyContinue
        Read-Host "Turn Smart App Control Off in the window that just opened, then press Enter here to continue (Enter alone continues with it on)"
        try {
            $sac = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -ErrorAction Stop).VerifiedAndReputablePolicyState
            $sacOn = ($sac -eq 1)
        } catch {}
        if (-not $sacOn) { Write-Host "[ok] Smart App Control is no longer blocking." -ForegroundColor Green }
    }

    $wslExe = "$env:windir\System32\wsl.exe"
    $psExe  = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    $ok = @(); $deja = @(); $echec = @()
    $startMenus = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")
    $racinesExe = @("$env:LOCALAPPDATA\Microsoft\WinGet\Links", "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "$env:LOCALAPPDATA\Programs", $Dossier)

    # ---------- Helpers ----------
    function Get-File($url, $out) {
        try { Invoke-WebRequest $url -OutFile $out -UseBasicParsing -ErrorAction Stop } catch {}
        if ((Test-Path $out) -and ((Get-Item $out).Length -gt 1000)) { return $true }
        Remove-Item $out -Force -ErrorAction SilentlyContinue
        curl.exe -L --ssl-no-revoke -sS -o $out $url 2>$null
        if ((Test-Path $out) -and ((Get-Item $out).Length -gt 1000)) { return $true }
        Remove-Item $out -Force -ErrorAction SilentlyContinue
        return $false
    }
    function Get-Json($url) {
        try { return Invoke-RestMethod $url -UseBasicParsing -ErrorAction Stop } catch {}
        try { return (((curl.exe -sSL --ssl-no-revoke $url 2>$null) -join "`n") | ConvertFrom-Json) } catch { return $null }
    }
    # Name of the installed WSL distro (Kali preferred), or $null
    function Get-Distro {
        $l = & $wslExe -l -q 2>$null
        $names = @($l | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ -match '^[A-Za-z0-9._-]+$' -and $_ -notlike "docker-desktop*" })
        $k = $names | Where-Object { $_ -like "kali*" } | Select-Object -First 1
        if ($k) { return $k }
        return ($names | Select-Object -First 1)
    }
    # Kali already installed but WSL not usable yet (reboot pending): "wsl -l" returns nothing in that case
    function Test-KaliPackage {
        $reg = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-ItemProperty $_.PSPath).DistributionName } | Where-Object { $_ -like "kali*" }
        if ($reg) { return $true }
        if (Get-AppxPackage -Name "*Kali*" -ErrorAction SilentlyContinue) { return $true }
        return $false
    }
    # Full path of a REAL python.exe, or $null.
    # "python" alone is often the Microsoft Store stub (prints "Python est introuvable"),
    # so we try the "py" launcher first and check that the interpreter really runs.
    function Find-Python {
        $cands = @()
        if (Get-Command py -ErrorAction SilentlyContinue) {
            $r = & py -3 -c "import sys;print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $r) { $cands += ($r | Select-Object -First 1).Trim() }
        }
        $cands += @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python", "$env:ProgramFiles\Python*" -Filter python.exe -Recurse -Depth 1 -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        $g = Get-Command python -ErrorAction SilentlyContinue
        if ($g -and $g.Source -notlike "*\WindowsApps\*") { $cands += $g.Source }
        foreach ($c in $cands) {
            if ($c -and (Test-Path $c)) {
                & $c -c "import sys" 2>$null
                if ($LASTEXITCODE -eq 0) { return $c }
            }
        }
        return $null
    }
    # Is a program with this display name registered in Windows (Apps and features)?
    function Test-Uninstall($motif) {
        foreach ($k in "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*") {
            $f = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $motif } | Select-Object -First 1
            if ($f) { return $true }
        }
        return $false
    }
    # Full path of $Marker in $Dir or up to 3 folder levels below it, else $null
    function Find-Marker($Dir, $Marker) {
        if (-not (Test-Path $Dir)) { return $null }
        $level = @($Dir)
        for ($i = 0; $i -lt 4; $i++) {
            foreach ($d in $level) {
                $c = Join-Path $d $Marker
                if (Test-Path $c) { return $c }
            }
            $level = @($level | ForEach-Object { Get-ChildItem $_ -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } })
            if (-not $level) { break }
        }
        return $null
    }
    # Is a Start Menu shortcut matching this pattern present?
    function Test-StartMenu($motif) {
        foreach ($m in $startMenus) {
            $f = Get-ChildItem $m -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -like $motif } | Select-Object -First 1
            if ($f) { return $true }
        }
        return $false
    }
    # Download the first release asset of a GitHub repo that matches a pattern, unzip it into $Dest.
    # Skipped if $Marker (a file name) already exists somewhere under $Dest.
    function Install-GitHubZip($Nom, $Repo, $Pattern, $Dest, $Marker) {
        $found = Find-Marker $Dest $Marker
        if ($found) {
            Write-Host "[already installed] $Nom ($found)" -ForegroundColor Yellow; $script:deja += $Nom; return
        }
        Write-Host "[installing] $Nom (GitHub)... ($Marker not found under $Dest)" -ForegroundColor Cyan
        $rel = Get-Json "https://api.github.com/repos/$Repo/releases/latest"
        $asset = $rel.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1
        $zip = "$Tools\$Nom.zip"
        if ($asset -and (Get-File $asset.browser_download_url $zip)) {
            try {
                Expand-Archive $zip -DestinationPath $Dest -Force
                $script:ok += $Nom
            } catch { $script:echec += $Nom }
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
        } else { $script:echec += $Nom }
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget not found. Install 'App Installer' from the Microsoft Store."
    }

    # ---------- 1. winget programs ----------
    # Ids = several ids are tried in order until one works (winget ids sometimes change)
    $apps = @(
        @{ Nom = "Git";           Ids = @("Git.Git");                          Cmd = "git" },
        @{ Nom = "Python 3";      Ids = @("Python.Python.3.12");               Cmd = "py" },
        @{ Nom = "Java";          Ids = @("Microsoft.OpenJDK.21");             Cmd = "java" },
        @{ Nom = "VS Code";       Ids = @("Microsoft.VisualStudioCode");       Cmd = "code" },
        @{ Nom = "7-Zip";         Ids = @("7zip.7zip");                        Cmd = "" },
        @{ Nom = "Audacity";      Ids = @("Audacity.Audacity");                Cmd = "" },
        @{ Nom = "ExifTool";      Ids = @("OliverBetz.ExifTool");              Cmd = "exiftool" },
        @{ Nom = "Wireshark";     Ids = @("WiresharkFoundation.Wireshark");    Cmd = "" },
        @{ Nom = "Nmap";          Ids = @("Insecure.Nmap");                    Cmd = "nmap" },
        @{ Nom = "Burp Suite CE"; Ids = @("PortSwigger.BurpSuite.Community");  Cmd = "" },
        @{ Nom = "x64dbg";        Ids = @("x64dbg.x64dbg");                    Cmd = "" },
        @{ Nom = "VirtualBox";    Ids = @("Oracle.VirtualBox");                Cmd = "" }
    )
    foreach ($a in $apps) {
        $present = $false
        if ($a.Cmd -and (Get-Command $a.Cmd -ErrorAction SilentlyContinue)) { $present = $true }
        if (-not $present) {
            foreach ($id in $a.Ids) {
                winget list --id $id --exact --accept-source-agreements *> $null
                if ($LASTEXITCODE -eq 0) { $present = $true; break }
            }
        }
        if ($present) { Write-Host "[already installed] $($a.Nom)" -ForegroundColor Yellow; $deja += $a.Nom; continue }
        Write-Host "[installing] $($a.Nom)..." -ForegroundColor Cyan
        $done = $false
        foreach ($id in $a.Ids) {
            winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -eq 0) { $done = $true; break }
        }
        if ($done) { $ok += $a.Nom } else { $echec += $a.Nom }
    }

    # ---------- 2. WSL 2: Kali + Linux tools ----------
    wsl --set-default-version 2 2>$null | Out-Null
    $distro = Get-Distro
    if ($distro -like "kali*") {
        Write-Host "[already installed] Kali ($distro)" -ForegroundColor Yellow; $deja += "Kali"
    } elseif (Test-KaliPackage) {
        Write-Host "[already installed] Kali (WSL not usable yet: restart the PC, then run this script again for the Linux tools)" -ForegroundColor Yellow
        $deja += "Kali"; $echec += "Kali Linux tools skipped (restart the PC first)"
    } else {
        Write-Host "[installing] Kali (WSL)..." -ForegroundColor Cyan
        wsl --install -d kali-linux --no-launch
        $distro = Get-Distro
        if ($distro -like "kali*") { $ok += "Kali" } else { $echec += "Kali (restart the PC, then run this script again)" }
    }
    if ($distro -like "kali*") {
        Write-Host "[installing] Linux tools in Kali (only what is missing, can take a while)..." -ForegroundColor Cyan
        $sh = "$Tools\setup_kali.sh"
        $sageExtra = if ($InstallSage) { " sagemath" } else { "" }
        $kaliSh = @'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
FAIL=0
PKGS="git curl wget file xxd python3-pip python3-venv build-essential ruby-dev steghide binwalk foremost libimage-exiftool-perl gobuster ffuf john hashcat gdb ltrace strace netcat-traditional exploitdb metasploit-framework sqlmap radare2 python3-pwntools python3-scapy wordlists seclists jadx apktool aapt__SAGE__"

# apt: install only the packages that are missing, one by one so a single failure does not block the rest
MISSING=""
for p in $PKGS; do dpkg -s "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"; done
if [ -n "$MISSING" ]; then
  apt-get update -y
  for p in $MISSING; do
    apt-get install -y "$p" || { echo "[failed] $p"; FAIL=1; }
  done
else
  echo "[already installed] all apt packages"
fi

# zsteg (Ruby gem)
if command -v zsteg >/dev/null 2>&1; then echo "[already installed] zsteg"; else gem install zsteg || { echo "[failed] zsteg"; FAIL=1; }; fi

# rockyou.txt (shipped compressed in the wordlists package)
if [ -f /usr/share/wordlists/rockyou.txt.gz ] && [ ! -f /usr/share/wordlists/rockyou.txt ]; then
  gunzip -k /usr/share/wordlists/rockyou.txt.gz
fi

# pwndbg (GDB plugin), loaded for every user through /etc/gdb/gdbinit
if [ ! -f /opt/pwndbg/gdbinit.py ]; then
  rm -rf /opt/pwndbg
  if git clone --depth 1 https://github.com/pwndbg/pwndbg /opt/pwndbg; then
    (cd /opt/pwndbg && ./setup.sh) || { echo "[failed] pwndbg setup"; FAIL=1; }
  else
    echo "[failed] pwndbg clone"; FAIL=1
  fi
else
  echo "[already installed] pwndbg"
fi
if [ -f /opt/pwndbg/gdbinit.py ] && ! grep -q "/opt/pwndbg/gdbinit.py" /etc/gdb/gdbinit 2>/dev/null; then
  mkdir -p /etc/gdb
  echo "source /opt/pwndbg/gdbinit.py" >> /etc/gdb/gdbinit
fi

exit $FAIL
'@
        $kaliSh = $kaliSh.Replace("__SAGE__", $sageExtra)
        [IO.File]::WriteAllText($sh, ($kaliSh -replace "`r`n", "`n"))
        $shWsl = "/mnt/" + $sh.Substring(0,1).ToLower() + $sh.Substring(2).Replace("\", "/")
        & $wslExe -d $distro -u root -- bash $shWsl
        if ($LASTEXITCODE -eq 0) { $ok += "Kali Linux tools" } else { $echec += "Kali Linux tools (some packages failed, run the script again)" }
    }

    # ---------- 3. Python libraries (Windows) ----------
    $env:Path = $env:Path + ";" + [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    # Real Python (works with "py" even if "python" is only the Microsoft Store stub)
    $pyExe = Find-Python
    if ($pyExe) { Write-Host "[python] Using $pyExe" -ForegroundColor Cyan }
    if ($pyExe) {
        & $pyExe -m pip install --upgrade pip --disable-pip-version-check --quiet --no-warn-script-location 2>$null
        & $pyExe -m pip cache purge --disable-pip-version-check *> $null     # fixes the "Cache entry deserialization failed" warnings
        # Make the Scripts folders of this Python visible, so tools like "pwn" can be detected
        foreach ($d in (& $pyExe -c "import sysconfig,site,os;print(sysconfig.get_path('scripts'));print(os.path.join(site.getuserbase(),'Scripts'))" 2>$null)) {
            if ($d -and (Test-Path $d) -and (($env:Path -split ";") -notcontains $d)) { $env:Path = "$env:Path;$d" }
        }
        $installed = (& $pyExe -m pip list --format=freeze 2>$null) -replace "==.*", ""
        foreach ($p in "requests","pwntools","beautifulsoup4","scapy","sqlmap","pycryptodome","sympy","pillow") {
            $already = $installed -contains $p
            # pwntools may be installed elsewhere (another Python): the "pwn" command or "import pwn" is enough
            if ($p -eq "pwntools" -and -not $already) {
                if (Get-Command pwn -ErrorAction SilentlyContinue) { $already = $true }
                else { & $pyExe -c "import pwn" *> $null; if ($LASTEXITCODE -eq 0) { $already = $true } }
            }
            if ($already) { Write-Host "[already installed] pip $p" -ForegroundColor Yellow; $deja += "pip $p" }
            else {
                Write-Host "[pip] $p..." -ForegroundColor Cyan
                & $pyExe -m pip install --disable-pip-version-check --no-warn-script-location $p
                if ($LASTEXITCODE -eq 0) { $ok += "pip $p" }
                elseif ($p -eq "pwntools") { $echec += "pip pwntools (its unicorn dependency cannot be built on this Python version: use pwntools in Kali, it is installed there)" }
                else { $echec += "pip $p" }
            }
        }
    } else { $echec += "pip (python not found, restart then run again)" }

    # ---------- 4. GitHub repos (zip, no git needed) ----------
    $repos = @{
        "PayloadsAllTheThings" = "swisskyrepo/PayloadsAllTheThings"
        "RsaCtfTool"           = "RsaCtfTool/RsaCtfTool"
        "PEASS-ng"             = "peass-ng/PEASS-ng"
        "volatility3"          = "volatilityfoundation/volatility3"
        "BeEF"                 = "beefproject/beef"
    }
    foreach ($r in $repos.GetEnumerator()) {
        if (Test-Path "$Tools\$($r.Key)") {
            Write-Host "[already installed] $($r.Key)" -ForegroundColor Yellow; $deja += $r.Key; continue
        }
        Write-Host "[downloading] $($r.Key)..." -ForegroundColor Cyan
        $zip = "$Tools\$($r.Key).zip"
        if (Get-File "https://github.com/$($r.Value)/archive/HEAD.zip" $zip) {
            $tmp = "$Tools\_tmp_$($r.Key)"
            Expand-Archive $zip -DestinationPath $tmp -Force
            Move-Item (Get-ChildItem $tmp | Select-Object -First 1).FullName "$Tools\$($r.Key)"
            Remove-Item $tmp, $zip -Recurse -Force
            $ok += $r.Key
        } else { $echec += $r.Key }
    }

    # ---------- 5. Stegsolve ----------
    if (Test-Path "$Tools\stegsolve.jar") {
        Write-Host "[already installed] Stegsolve" -ForegroundColor Yellow; $deja += "Stegsolve"
    } else {
        Write-Host "[downloading] Stegsolve..." -ForegroundColor Cyan
        $got = (Get-File "http://www.caesum.com/handbook/Stegsolve.jar" "$Tools\stegsolve.jar") -or `
               (Get-File "https://github.com/eugenekolo/sec-tools/raw/master/stego/stegsolve/stegsolve/stegsolve.jar" "$Tools\stegsolve.jar")
        if ($got) { $ok += "Stegsolve" } else { $echec += "Stegsolve" }
    }

    # ---------- 5b. CyberChef (offline copy, one HTML file, opens in the browser) ----------
    Install-GitHubZip "CyberChef" "gchq/CyberChef" "CyberChef_*.zip" "$Tools\CyberChef" "CyberChef_*.html"

    # ---------- 6. Ghidra, Cutter, Autopsy (GitHub releases) ----------
    Install-GitHubZip "Ghidra" "NationalSecurityAgency/ghidra" "*.zip" "$Tools\Ghidra" "ghidraRun.bat"
    Install-GitHubZip "Cutter" "rizinorg/cutter" "*Windows*x86_64*.zip" "$Tools\Cutter" "cutter.exe"

    $autopsyWhere = $null
    if (Test-Uninstall "Autopsy*") { $autopsyWhere = "Windows installed apps list" }
    elseif (Test-StartMenu "Autopsy*") { $autopsyWhere = "Start Menu" }
    else {
        foreach ($pf in $env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs") {
            $d = Get-ChildItem $pf -Directory -Filter "Autopsy*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($d) { $autopsyWhere = $d.FullName; break }
        }
    }
    if ($autopsyWhere) {
        Write-Host "[already installed] Autopsy ($autopsyWhere)" -ForegroundColor Yellow; $deja += "Autopsy"
    } else {
        Write-Host "[installing] Autopsy (GitHub)... (not found in installed apps, Start Menu or Program Files)" -ForegroundColor Cyan
        $good = $false
        $rel = Get-Json "https://api.github.com/repos/sleuthkit/autopsy/releases/latest"
        $asset = $rel.assets | Where-Object { $_.name -like "*.msi" } | Select-Object -First 1
        if ($asset -and (Get-File $asset.browser_download_url "$Tools\autopsy.msi")) {
            Start-Process msiexec.exe -ArgumentList "/i `"$Tools\autopsy.msi`" /qn" -Wait
            Remove-Item "$Tools\autopsy.msi" -Force
            $good = $true
        }
        if ($good) { $ok += "Autopsy" } else { $echec += "Autopsy" }
    }

    # ==========================================================
    #  7. Category folders + shortcuts
    # ==========================================================
    Write-Host ""
    Write-Host "[shortcuts] Building category folders..." -ForegroundColor Cyan

    $sep = " " + [char]0x00A6 + " "     # looks like a pipe (a real | is not allowed in file names)

    # Helper used by the ExifTool shortcut: city found online from the GPS coordinates (always rewritten)
    Set-Content -Path "$Tools\exifgeo.ps1" -Encoding UTF8 -Value @'
# Prints the city found online (OpenStreetMap Nominatim) from the GPS coordinates of each file.
# The coordinates are sent to nominatim.openstreetmap.org (needs internet).
param([Parameter(ValueFromRemainingArguments = $true)] $Files)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
foreach ($f in $Files) {
    if (("$f" -like "-*") -or -not (Test-Path "$f" -PathType Leaf)) { continue }
    $gps = @(& exiftool.exe -n -s3 -GPSLatitude -GPSLongitude "$f" 2>$null)
    if ($gps.Count -lt 2) { continue }
    $lat = ("$($gps[0])").Trim(); $lon = ("$($gps[1])").Trim()
    try {
        $u = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=fr&lat=$lat&lon=$lon"
        $resp = Invoke-WebRequest $u -Headers @{ "User-Agent" = "RootMe-Tools/1.0" } -UseBasicParsing -TimeoutSec 15
        $r = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
        $a = $r.address
        $ville = @($a.city, $a.town, $a.village, $a.municipality, $a.county) | Where-Object { $_ } | Select-Object -First 1
        Write-Host ""
        Write-Host "Online city (OpenStreetMap) for $f : $ville" -ForegroundColor Green
        Write-Host "  $($r.display_name)"
    } catch {
        Write-Host "Online lookup failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
'@

    # Decode a raw hex frame dump (Ethernet/IP/TCP/UDP...) pasted interactively, using Scapy.
    # Used by the "Scapy - Decode Hex Frame" shortcut below.
    $hexframePy = @'
#!/usr/bin/env python3
"""Paste a raw hex frame dump (the kind of "00 05 73 a0 ..." block Root-Me gives you for
network challenges), then press Enter on an empty line (or Ctrl+D) to decode it.
Shows every layer Scapy recognizes (Ethernet, IP/IPv6, TCP/UDP...) and, if there is a
payload, prints it as text too (useful for HTTP/FTP/Telnet-style challenges)."""
import sys
from scapy.all import Ether

print("Paste the hex bytes below (spaces/newlines are both fine).")
print("Press Enter on an empty line, or Ctrl+D, when you are done:\n")
lines = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        break
    lines.append(line)

hexstr = "".join(lines).replace(" ", "")
try:
    data = bytes.fromhex(hexstr)
except ValueError as e:
    print(f"Could not parse that as hex: {e}")
    sys.exit(1)

pkt = Ether(data)
print("\n========== Decoded layers ==========")
pkt.show()

if pkt.haslayer("Raw"):
    print("========== Payload as text ==========")
    print(pkt["Raw"].load.decode(errors="replace"))
'@
    # Written without a BOM and with LF-only line endings: a BOM at the start of a shebang
    # line makes bash try to execute "#!/bin/bash" as a literal command instead of treating
    # it as a comment, and breaks some interpreters' first-line parsing too.
    [IO.File]::WriteAllText("$Tools\hexframe.py", ($hexframePy -replace "`r`n", "`n"))

    # All-in-one, step-by-step APK/XAPK recon: unzips xapk if needed, dumps the manifest,
    # decompiles with jadx, and tells you exactly where everything landed and what to do next.
    # Used by the "Android - Full Recon (guided)" shortcut below.
    $androidReconSh = @'
#!/bin/bash
# Guided, in-order recon of an .apk or .xapk file. Run it, type the file name
# (it must be in this Workspace folder), and it does everything in the right order.
set -uo pipefail
echo "=================================================================="
echo " Android recon - guided, step by step"
echo "=================================================================="
echo
echo "Files currently in this folder:"
ls -1 -- *.apk *.xapk 2>/dev/null
echo
read -rp "Type the .apk or .xapk file name to analyze: " INPUT
if [ ! -f "$INPUT" ]; then
    echo "File not found: $INPUT (it must be in this Workspace folder, drop it there first)"
    exit 1
fi

ORIGINAL_DIR="$(pwd)"
BASENAME="$(basename "$INPUT")"
NAME="${BASENAME%.*}"
APK="$INPUT"

# Windows drives mounted in WSL (/mnt/c/...) use the 9p protocol, which some Java tools
# (jadx in particular) cannot reliably create nested directories on. Do all the real work
# on Kali's own native filesystem instead, then copy the results back to Workspace at the end.
WORKDIR="$HOME/.rootme-android-work/$NAME"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cp "$INPUT" "$WORKDIR/"
cd "$WORKDIR" || exit 1
INPUT="$BASENAME"
APK="$INPUT"

# Step 0: if it's an XAPK (a zip with the real apk inside), unzip it and find the base apk
if [[ "$INPUT" == *.xapk ]]; then
    echo
    echo "---------------------------------------------------------------"
    echo "STEP 0: .xapk detected -> unzipping it (it's just a zip of apks)"
    echo "---------------------------------------------------------------"
    EXTRACT_DIR="${NAME}_extracted"
    mkdir -p "$EXTRACT_DIR"
    unzip -o -q "$INPUT" -d "$EXTRACT_DIR"
    echo "Extracted into: $EXTRACT_DIR"
    echo "Contents:"
    ls -1 "$EXTRACT_DIR"
    APK=$(find "$EXTRACT_DIR" -iname "base.apk" -o -iname "*.apk" ! -iname "config.*" | head -n 1)
    if [ -z "$APK" ]; then APK=$(find "$EXTRACT_DIR" -iname "*.apk" | head -n 1); fi
    echo
    echo ">>> Using this file as the main APK for the rest: $APK"
    echo "    (the other config.*.apk files are just language/CPU splits, usually no code of interest)"
fi

# jadx's own wrapper script changes directory internally before running, which breaks a
# relative path - always use an absolute path for every tool from here on.
APK="$(realpath "$APK")"

# Step 1: aapt - quick identity card of the app (permissions, exported components)
echo
echo "---------------------------------------------------------------"
echo "STEP 1: aapt - manifest summary (permissions, exported components)"
echo "---------------------------------------------------------------"
aapt dump badging "$APK" > "${NAME}_aapt.txt" 2>&1
echo "Saved to: ${NAME}_aapt.txt"
echo
echo "Permissions requested:"
grep -i "uses-permission" "${NAME}_aapt.txt" | sed 's/^/  /'
echo
echo "Exported components (the first thing to check for an easy attack surface):"
grep -i "exported" "${NAME}_aapt.txt" | sed 's/^/  /'
if ! grep -qi "exported" "${NAME}_aapt.txt"; then
    echo "  (aapt didn't print any directly here - open ${NAME}_aapt.txt and check the full"
    echo "   AndroidManifest.xml from apktool in step 3 if you need the exported= flags precisely)"
fi

# Step 2: jadx - decompile to readable Java (the main step, read this first)
echo
echo "---------------------------------------------------------------"
echo "STEP 2: jadx - decompiling to readable Java (this is the main step)"
echo "---------------------------------------------------------------"
rm -rf "${NAME}_jadx"
jadx -d "${NAME}_jadx" "$APK" > "${NAME}_jadx.log" 2>&1
if [ -d "${NAME}_jadx/sources" ]; then
    echo "Decompiled Java code is in: ${NAME}_jadx/sources/"
    echo "Open that folder in VS Code to read it, or search it directly, e.g.:"
    echo "  grep -ri 'password\|secret\|api_key\|token' -r ${NAME}_jadx/sources/"
else
    echo "jadx did not produce sources (see ${NAME}_jadx.log) - this is normal for heavily"
    echo "obfuscated or packed apps. Move on to apktool (step 3) for the smali instead."
fi

# Step 3: apktool - smali + raw resources, as a fallback / for patching
echo
echo "---------------------------------------------------------------"
echo "STEP 3: apktool - smali + raw resources (fallback, or to patch and rebuild)"
echo "---------------------------------------------------------------"
echo "(on the very first run, apktool downloads an Android framework file from the internet"
echo " the first time it needs it - this can take a minute with no output, that's normal)"
apktool d -f -o "${NAME}_apktool" "$APK" > "${NAME}_apktool.log" 2>&1
if [ -d "${NAME}_apktool" ]; then
    echo "Unpacked into: ${NAME}_apktool/"
    echo "  ${NAME}_apktool/AndroidManifest.xml   -> full manifest, readable"
    echo "  ${NAME}_apktool/smali*/                -> bytecode, use only if jadx's Java was unreadable"
    echo "  ${NAME}_apktool/res/                    -> app resources (strings, layouts...)"
    echo "To repack after editing: apktool b ${NAME}_apktool -o patched.apk"
else
    echo "apktool failed (see ${NAME}_apktool.log)"
fi

# Copy everything back next to the original file in Workspace, so you can see/open it
# from Windows too, then clean up the native-filesystem working copy.
RESULT_DIR="${ORIGINAL_DIR}/${NAME}_results"
rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"
cp -r "$WORKDIR"/* "$RESULT_DIR/" 2>/dev/null
rm -f "$RESULT_DIR/$BASENAME"   # no need to duplicate the original apk/xapk
cd "$ORIGINAL_DIR" || exit 1
rm -rf "$WORKDIR"

echo
echo "=================================================================="
echo " DONE. Everything was copied into: ${NAME}_results/"
echo " Suggested order to actually look at things:"
echo "   1. ${NAME}_results/${NAME}_aapt.txt                    - permissions & exported components"
echo "   2. ${NAME}_results/${NAME}_jadx/sources/                - read the real code here first"
echo "   3. ${NAME}_results/${NAME}_apktool/AndroidManifest.xml  - only if you need manifest details aapt missed"
echo "   4. ${NAME}_results/${NAME}_apktool/smali*/               - only if jadx's Java was broken/unreadable"
echo "=================================================================="
'@
    # Same no-BOM / LF-only fix as hexframe.py above.
    [IO.File]::WriteAllText("$Tools\android_recon.sh", ($androidReconSh -replace "`r`n", "`n"))

    $manquants = @()
    $ws = New-Object -ComObject WScript.Shell
    $distro = Get-Distro
    $dArg = if ($distro) { "-d $distro --" } else { "--" }
    $WorkWsl = "/mnt/" + $Work.Substring(0,1).ToLower() + $Work.Substring(2).Replace("\", "/")
    $ToolsWsl = "/mnt/" + $Tools.Substring(0,1).ToLower() + $Tools.Substring(2).Replace("\", "/")

    # Helper for the "Scapy - Decode Hex Frame" shortcut: makes sure python3-scapy is installed
    # in Kali (silently, as root via "wsl -u root" - this needs no Linux user password at all,
    # since WSL lets Windows pick the Linux user directly) before running hexframe.py.
    if ($distro) {
        $decodeScript = @"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Write-Host "Scapy - Decode Hex Frame" -ForegroundColor Green
Write-Host "Making sure python3-scapy is installed in Kali (runs as root, no password needed)..." -ForegroundColor DarkGray
& "$wslExe" -d $distro -u root -- bash -c "dpkg -s python3-scapy >/dev/null 2>&1 || (apt-get update -y >/dev/null 2>&1; apt-get install -y python3-scapy >/dev/null 2>&1)"
Write-Host ""
Write-Host "Paste a raw hex frame dump (Root-Me network challenges), it gets decoded automatically."
Write-Host ""
& "$wslExe" -d $distro -- bash -c "cd '$WorkWsl'; python3 '$ToolsWsl/hexframe.py'; exec bash"
"@
        Set-Content -Path "$Tools\decode_hex_frame.ps1" -Encoding UTF8 -Value $decodeScript
    }

    # Folders added to PATH inside the shortcut terminals (exiftool, nmap, java, python scripts)
    $extra = @()
    function Add-ExtraDir($name, $filter) {
        if (Get-Command $name -ErrorAction SilentlyContinue) { return }
        foreach ($r in $racinesExe) {
            if (-not (Test-Path $r)) { continue }
            $f = Get-ChildItem $r -Recurse -Filter $filter -ErrorAction SilentlyContinue -Depth 4 | Select-Object -First 1
            if ($f) { $script:extra += $f.DirectoryName; return }
        }
    }
    Add-ExtraDir "exiftool" "exiftool*.exe"
    Add-ExtraDir "nmap" "nmap.exe"
    Add-ExtraDir "java" "java.exe"
    $pyExe = Find-Python
    if ($pyExe) {
        $extra += (Split-Path $pyExe)
        foreach ($d in (& $pyExe -c "import sysconfig,site,os;print(sysconfig.get_path('scripts'));print(os.path.join(site.getuserbase(),'Scripts'))" 2>$null)) {
            if ($d -and (Test-Path $d)) { $extra += $d }
        }
    }
    $extraPath = ($extra | Select-Object -Unique) -join ";"

    function Get-Cat($nom) {
        $p = Join-Path $Racine $nom
        New-Item -ItemType Directory -Force -Path $p | Out-Null
        return $p
    }
    function New-Lnk($chemin, $cible, $arguments) {
        $s = $ws.CreateShortcut($chemin)
        $s.TargetPath = $cible
        if ($arguments) { $s.Arguments = $arguments }
        $s.WorkingDirectory = $env:USERPROFILE
        $s.Save()
    }
    # Missing tool: a .txt named like the shortcut, with the download link
    function Add-Missing($cat, $label, $url, $note) {
        $txt = "Tool: $label`r`nStatus: NOT INSTALLED`r`nDownload it here: $url`r`n"
        if ($note) { $txt += "$note`r`n" }
        Set-Content -Path (Join-Path (Get-Cat $cat) "$label.txt") -Value $txt -Encoding ASCII
        $script:manquants += $label
    }
    # GUI program: Start Menu shortcut first, then search for the exe
    function Add-App($cat, $label, $motif, $exe, $url, $note) {
        $dest = Join-Path (Get-Cat $cat) "$label.lnk"
        $trouve = $null
        foreach ($m in $startMenus) {
            $trouve = Get-ChildItem $m -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -like $motif } | Select-Object -First 1
            if ($trouve) { break }
        }
        if ($trouve) { Copy-Item $trouve.FullName $dest -Force; return }
        if ($exe) {
            foreach ($r in $racinesExe) {
                if (-not (Test-Path $r)) { continue }
                $f = Get-ChildItem $r -Recurse -Filter $exe -ErrorAction SilentlyContinue -Depth 5 | Select-Object -First 1
                if ($f) { New-Lnk $dest $f.FullName ""; return }
            }
        }
        Add-Missing $cat $label $url $note
    }
    # Windows terminal: banner with an example, opens in the Workspace folder
    function Add-Cmd($cat, $label, $example, $run) {
        $cmd = "[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$env:Path += ';$extraPath'; Set-Location '$Work'; Write-Host '$label' -ForegroundColor Green; Write-Host 'Example: $example'; Write-Host 'Your files go in: $Work'; Write-Host ''"
        if ($run) { $cmd += "; $run" }
        New-Lnk (Join-Path (Get-Cat $cat) "$label.lnk") $psExe "-NoExit -ExecutionPolicy Bypass -Command `"$cmd`""
    }
    # Kali terminal: banner with an example, opens in the Workspace folder
    function Add-Wsl($cat, $label, $example, $run) {
        $inner = "cd '$WorkWsl'; echo '$label'; "
        if ($example) { $inner += "echo 'Example: $example'; " }
        $inner += "echo; "
        if ($run) { $inner += "$run; " }
        $inner += "exec bash"
        New-Lnk (Join-Path (Get-Cat $cat) "$label.lnk") $wslExe "$dArg bash -c `"$inner`""
    }
    function Add-Dossier($cat, $label, $chemin, $url) {
        if (Test-Path $chemin) { New-Lnk (Join-Path (Get-Cat $cat) "$label.lnk") $chemin "" } else { Add-Missing $cat $label $url "" }
    }
    function Add-Url($cat, $label, $url) {
        Set-Content -Path (Join-Path (Get-Cat $cat) "$label.url") -Value "[InternetShortcut]`r`nURL=$url" -Encoding ASCII
    }
    # CyberChef: offline copy only. If the zip was not downloaded, a .txt with the
    # GitHub releases link is created instead (no online fallback: see Install-GitHubZip above).
    function Add-CyberChef($cat) {
        $html = Get-ChildItem "$Tools\CyberChef" -Recurse -Filter "CyberChef_*.html" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($html) { New-Lnk (Join-Path (Get-Cat $cat) "CyberChef - Data Conversion.lnk") $html.FullName "" }
        else { Add-Missing $cat "CyberChef - Data Conversion" "https://github.com/gchq/CyberChef/releases/latest" "Download the CyberChef_*.zip asset, unzip it into $Tools\CyberChef, then run the script again." }
    }
    # VS Code opened directly on the Workspace folder
    function Add-VSCode($cat) {
        $codeExe = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe", "$env:ProgramFiles\Microsoft VS Code\Code.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($codeExe) { New-Lnk (Join-Path (Get-Cat $cat) "VS Code - Open Workspace.lnk") $codeExe ('"' + $Work + '"') }
        else { Add-Missing $cat "VS Code - Open Workspace" "https://code.visualstudio.com/" "" }
    }

    $c = "00-Prerequisites${sep}Prerequis"
    Add-Dossier $c "Workspace - Challenge Files" $Work ""
    Add-VSCode $c
    Add-App $c "7-Zip - Archives" "7-Zip*" "7zFM.exe" "https://www.7-zip.org/" ""
    Add-App $c "VirtualBox - Virtual Machine" "*VirtualBox*" "VirtualBox.exe" "https://www.virtualbox.org/wiki/Downloads" ""
    Add-Wsl $c "Kali - Linux Terminal" "ls then cd to your files" ""

    $c = "01-Steganography${sep}Steganographie"
    Add-Cmd $c "ExifTool - Read Metadata" "exiftool image.jpg" "function exiftool { & exiftool.exe -a -u -ee -api Geolocation -c '%.13f' `@args; & '$Tools\exifgeo.ps1' `@args }; Write-Host 'Shows the ExifTool place name, then the city found online from the GPS coordinates'; exiftool -ver"
    if (Test-Path "$Tools\stegsolve.jar") { Add-Cmd $c "Stegsolve - Color Planes" "open your image with File then Open" "java -jar '$Tools\stegsolve.jar'" }
    else { Add-Missing $c "Stegsolve - Color Planes" "http://www.caesum.com/handbook/Stegsolve.jar" "Save Stegsolve.jar as $Tools\stegsolve.jar (needs Java)." }
    Add-Wsl $c "Steghide - Extract Hidden" "steghide extract -sf image.jpg" "steghide --version"
    Add-Wsl $c "Zsteg - PNG LSB" "zsteg image.png" "zsteg --version"
    Add-App $c "HxD - Hex Editor" "HxD*" "HxD*.exe" "https://mh-nexus.de/en/hxd/" "Check magic bytes (file headers) here."
    Add-App $c "Audacity - Audio Spectrogram" "*Audacity*" "Audacity.exe" "https://www.audacityteam.org/download/" "Track menu, then Spectrogram view."

    $c = "02-Web-Client"
    Add-Url $c "XSS Hunter - Blind XSS" "https://xsshunter.com/"
    Add-Dossier $c "BeEF - Browser Exploitation" "$Tools\BeEF" "https://github.com/beefproject/beef"

    $c = "03-Programming${sep}Programmation"
    Add-VSCode $c
    Add-Cmd $c "Pwntools - Network Scripting" "from pwn import * then remote(host, port)" "pwn version"
    Add-CyberChef $c

    $c = "04-Network${sep}Reseau"
    Add-App $c "Wireshark - Packet Analysis" "*Wireshark*" "Wireshark.exe" "https://www.wireshark.org/download.html" ""
    Add-Cmd $c "Nmap - Port Scan" "nmap -sV -p- target" "nmap --version"
    Add-Wsl $c "Netcat - TCP Connections" "nc host port" "nc -h 2>&1 | head -n 3"
    Add-Cmd $c "Scapy - Packet Forging" "sniff(count=5) then packets.summary()" "scapy"
    if ($distro) {
        New-Lnk (Join-Path (Get-Cat $c) "Scapy - Decode Hex Frame.lnk") $psExe "-NoExit -ExecutionPolicy Bypass -File `"$Tools\decode_hex_frame.ps1`""
    } else {
        Add-Missing $c "Scapy - Decode Hex Frame" "" "No WSL distro found: install Kali first, then run the script again."
    }

    $c = "05-Web-Server${sep}Web-Serveur"
    Add-App $c "Burp - HTTP Proxy" "*Burp*" "BurpSuiteCommunity.exe" "https://portswigger.net/burp/communitydownload" ""
    Add-Wsl $c "Gobuster - Hidden Directories" "gobuster dir -u URL -w /usr/share/seclists/Discovery/Web-Content/common.txt" "gobuster version"
    Add-Wsl $c "ffuf - Web Fuzzing" "ffuf -u URL/FUZZ -w /usr/share/seclists/Discovery/Web-Content/common.txt" "ffuf -V"
    Add-Cmd $c "SQLmap - SQL Injection" "sqlmap -u http://target/page?id=1 --dbs" "sqlmap --version"
    Add-Dossier $c "Payloads - Payload Library" "$Tools\PayloadsAllTheThings" "https://github.com/swisskyrepo/PayloadsAllTheThings"

    $c = "06-Cryptanalysis${sep}Cryptanalyse"
    Add-CyberChef $c
    Add-Url $c "dCode - Classic Ciphers" "https://www.dcode.fr/"
    Add-Dossier $c "RsaCtfTool - Break RSA" "$Tools\RsaCtfTool" "https://github.com/RsaCtfTool/RsaCtfTool"
    Add-Wsl $c "Hashcat - Crack Hashes" "" "printf '  1. echo 31d6cfe0d16ae931b73c59d7e0c089c0 > hash.txt\n  2. hashcat -m 0 hash.txt /usr/share/wordlists/rockyou.txt\n       -m sets the hash type: 0=MD5  100=SHA1  1000=NTLM  1800=sha512crypt   (-a 3 = brute-force mode)\n  3. hashcat -m 0 hash.txt --show\n       re-shows a hash already cracked, does not re-crack it\n  4. rm hash.txt\n       cleanup once done; the cracked password stays cached in ~/.hashcat/hashcat.potfile,\n       delete that file too if you want --show to really forget it\n\n'; hashcat --version"
    Add-Wsl $c "John - Crack Passwords" "" "printf '  1. echo 31d6cfe0d16ae931b73c59d7e0c089c0 > hash.txt\n  2. john --format=raw-md5 --wordlist=/usr/share/wordlists/rockyou.txt hash.txt\n       omit --format and John auto-detects the hash type (slower); --list=formats shows all names\n  3. john --show hash.txt\n       re-shows a hash already cracked, does not re-crack it\n  4. rm hash.txt\n       cleanup once done; the cracked password stays cached in ~/.john/john.pot,\n       delete that file too if you want --show to really forget it\n\n'; john --version 2>&1 | head -n 1"
    Add-Wsl $c "Wordlists - rockyou and SecLists" "ls /usr/share/wordlists" "ls /usr/share/wordlists | head -n 20"
    if ($InstallSage) { Add-Wsl $c "SageMath - Math for Crypto" "sage then factor(N)" "sage" }

    $c = "07-App-Script"
    Add-Url $c "GTFOBins - Binary Exploits" "https://gtfobins.github.io/"
    Add-Dossier $c "PEASS - Privilege Escalation" "$Tools\PEASS-ng" "https://github.com/peass-ng/PEASS-ng"
    Add-Wsl $c "Kali - Linux Terminal" "sudo -l then find / -perm -4000 2>/dev/null" ""

    $c = "08-Forensic${sep}Forensique"
    Add-Wsl $c "Strings - Extract Text" "strings -n 8 file" "strings --version | head -n 1"
    Add-Wsl $c "Binwalk - Embedded Files" "binwalk -e file" "binwalk --help | head -n 3"
    Add-Wsl $c "Foremost - File Carving" "foremost -i file -o out" "foremost -V"
    Add-App $c "HxD - Hex Editor" "HxD*" "HxD*.exe" "https://mh-nexus.de/en/hxd/" ""
    Add-App $c "Autopsy - Disk Analysis" "Autopsy*" "autopsy64.exe" "https://www.autopsy.com/download/" ""
    Add-Dossier $c "Volatility - RAM Analysis" "$Tools\volatility3" "https://github.com/volatilityfoundation/volatility3"

    $c = "09-Cracking${sep}Retro-ingenierie"
    Add-Wsl $c "Strace - Syscall Tracing" "strace ./binary" "strace -V | head -n 1"
    Add-Wsl $c "Ltrace - Library Calls" "ltrace ./binary" "ltrace -V | head -n 1"
    Add-App $c "Ghidra - Decompile Code" "*Ghidra*" "ghidraRun.bat" "https://github.com/NationalSecurityAgency/ghidra/releases/latest" "Unzip it, then run ghidraRun.bat (needs Java 21)."
    Add-App $c "Cutter - Free Decompiler" "*Cutter*" "cutter.exe" "https://github.com/rizinorg/cutter/releases/latest" ""
    Add-App $c "x64dbg - Windows Debugger" "*x64dbg*" "x96dbg.exe" "https://github.com/x64dbg/x64dbg/releases/latest" ""
    Add-Wsl $c "Radare2 - Reverse CLI" "r2 -A ./binary then afl" "r2 -v | head -n 1"
    Add-App $c "IDA - Disassemble Code" "IDA Free*" "ida.exe" "https://hex-rays.com/ida-free" "Free Hex-Rays account required: download and install it yourself."

    $c = "10-App-System${sep}App-Systeme"
    Add-Wsl $c "GDB + pwndbg - Linux Debugger" "gdb ./binary then run" "gdb --version | head -n 1"
    Add-Wsl $c "Pwntools - Exploit Crafting (Kali)" "pwn checksec ./binary" "pwn version"
    Add-Cmd $c "Pwntools - Exploit Crafting (Windows)" "pwn checksec ./binary" "pwn version"

    $c = "11-Realistic${sep}Realiste"
    Add-Wsl $c "Metasploit - Exploit Framework" "search CVE-2017-0144" "msfconsole"
    Add-Wsl $c "Searchsploit - Exploit Search" "searchsploit apache 2.4" "searchsploit -h | head -n 5"
    Add-Cmd $c "Nmap - Port Scan" "nmap -sV -p- target" "nmap --version"
    Add-App $c "Burp - HTTP Proxy" "*Burp*" "BurpSuiteCommunity.exe" "https://portswigger.net/burp/communitydownload" ""

    $c = "12-Other${sep}Autres"
    Add-Wsl $c "Android - Reverse an APK (start here)" "" "echo 'Drop your .apk or .xapk into this Workspace folder first, then run this.'; echo 'It will unzip it if needed, run aapt + jadx + apktool in the right order,'; echo 'and tell you exactly where to look and in what order. Just answer the prompt below.'; echo; bash '$ToolsWsl/android_recon.sh'"

    Write-Host "Shortcuts in: $Racine" -ForegroundColor Green
    if ($manquants) { Write-Host "Missing (a .txt with the download link was created instead): $(($manquants | Select-Object -Unique) -join ', ')" -ForegroundColor Yellow }
    if (-not $distro) { Write-Host "No WSL distro found: Kali shortcuts will not work until Kali is installed (restart, then run the script again)." -ForegroundColor Yellow }
    Start-Process explorer.exe $Racine

    # ---------- Summary ----------
    Write-Host ""
    Write-Host "===== SUMMARY =====" -ForegroundColor Green
    Write-Host "Installed : $($ok -join ', ')"
    Write-Host "Already   : $($deja -join ', ')"
    if ($echec) { Write-Host "Failed    : $($echec -join ', ')" -ForegroundColor Red }
    if ($sacOn -and $echec) { Write-Host "Smart App Control is on: failures above may come from blocked unsigned installers." -ForegroundColor Yellow }
    if ($sacWasOn) {
        Write-Host ""
        Write-Host "Smart App Control was on before the script. Turn it back on now:" -ForegroundColor Yellow
        Write-Host "Windows Security, App and browser control, Smart App Control settings, then On." -ForegroundColor Yellow
        Write-Host "Warning: once it is on again, unsigned tools (ExifTool, x64dbg, Cutter...) may be blocked at launch." -ForegroundColor Yellow
        Start-Process "windowsdefender://appbrowser" -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host ""
    Read-Host "Press Enter to close"
}