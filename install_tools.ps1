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
    New-Item -ItemType Directory -Force -Path $Dossier, $Tools, $Work, $Racine | Out-Null
    Set-Location $Dossier

    # Only the Tools folder is excluded (PEASS, BeEF... are flagged as malware by Defender).
    # Workspace is NOT excluded: challenge files stay scanned.
    Write-Host "[configuration] Adding Windows Defender exclusion for the Tools folder..." -ForegroundColor Cyan
    Add-MpPreference -ExclusionPath $Tools -ErrorAction SilentlyContinue

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
        if ((Test-Path $Dest) -and (Get-ChildItem $Dest -Recurse -Filter $Marker -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            Write-Host "[already installed] $Nom" -ForegroundColor Yellow; $script:deja += $Nom; return
        }
        Write-Host "[installing] $Nom (GitHub)..." -ForegroundColor Cyan
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
        @{ Nom = "Python 3";      Ids = @("Python.Python.3.12");               Cmd = "python" },
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
PKGS="git curl wget file xxd python3-pip python3-venv build-essential ruby-dev steghide binwalk foremost libimage-exiftool-perl gobuster ffuf john hashcat gdb ltrace strace netcat-traditional exploitdb metasploit-framework sqlmap radare2 python3-pwntools wordlists seclists__SAGE__"

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
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $installed = (python -m pip list --format=freeze 2>$null) -replace "==.*", ""
        foreach ($p in "requests","pwntools","beautifulsoup4","scapy","sqlmap","pycryptodome","sympy","pillow") {
            if ($installed -contains $p) { Write-Host "[already installed] pip $p" -ForegroundColor Yellow; $deja += "pip $p" }
            else {
                Write-Host "[pip] $p..." -ForegroundColor Cyan
                python -m pip install $p
                if ($LASTEXITCODE -eq 0) { $ok += "pip $p" } else { $echec += "pip $p" }
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

    # ---------- 6. Ghidra, Cutter, Autopsy (GitHub releases) ----------
    Install-GitHubZip "Ghidra" "NationalSecurityAgency/ghidra" "*.zip" "$Tools\Ghidra" "ghidraRun.bat"
    Install-GitHubZip "Cutter" "rizinorg/cutter" "*Windows*x86_64*.zip" "$Tools\Cutter" "cutter.exe"

    $autopsyPresent = (Test-StartMenu "Autopsy*") -or (Get-ChildItem $env:ProgramFiles -Directory -Filter "Autopsy*" -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($autopsyPresent) {
        Write-Host "[already installed] Autopsy" -ForegroundColor Yellow; $deja += "Autopsy"
    } else {
        Write-Host "[installing] Autopsy (GitHub)..." -ForegroundColor Cyan
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

    $manquants = @()
    $ws = New-Object -ComObject WScript.Shell
    $distro = Get-Distro
    $dArg = if ($distro) { "-d $distro --" } else { "--" }
    $WorkWsl = "/mnt/" + $Work.Substring(0,1).ToLower() + $Work.Substring(2).Replace("\", "/")

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
    if (Get-Command python -ErrorAction SilentlyContinue) {
        foreach ($d in (python -c "import sysconfig,site,os;print(sysconfig.get_path('scripts'));print(os.path.join(site.getuserbase(),'Scripts'))" 2>$null)) {
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
        $cmd = "`$env:Path += ';$extraPath'; Set-Location '$Work'; Write-Host '$label' -ForegroundColor Green; Write-Host 'Example: $example'; Write-Host 'Your files go in: $Work'; Write-Host ''"
        if ($run) { $cmd += "; $run" }
        New-Lnk (Join-Path (Get-Cat $cat) "$label.lnk") $psExe "-NoExit -Command `"$cmd`""
    }
    # Kali terminal: banner with an example, opens in the Workspace folder
    function Add-Wsl($cat, $label, $example, $run) {
        $inner = "cd '$WorkWsl'; echo '$label'; echo 'Example: $example'; echo; "
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
    Add-Cmd $c "ExifTool - Read Metadata" "exiftool image.jpg" "function exiftool { & exiftool.exe -a -u -ee -api Geolocation -c '%.13f' `@args }; exiftool -ver"
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
    Add-Url $c "CyberChef - Data Conversion" "https://gchq.github.io/CyberChef/"

    $c = "04-Network${sep}Reseau"
    Add-App $c "Wireshark - Packet Analysis" "*Wireshark*" "Wireshark.exe" "https://www.wireshark.org/download.html" ""
    Add-Cmd $c "Nmap - Port Scan" "nmap -sV -p- target" "nmap --version"
    Add-Wsl $c "Netcat - TCP Connections" "nc host port" "nc -h 2>&1 | head -n 3"
    Add-Cmd $c "Scapy - Packet Forging" "sniff(count=5) then packets.summary()" "scapy"

    $c = "05-Web-Server${sep}Web-Serveur"
    Add-App $c "Burp - HTTP Proxy" "*Burp*" "BurpSuiteCommunity.exe" "https://portswigger.net/burp/communitydownload" ""
    Add-Wsl $c "Gobuster - Hidden Directories" "gobuster dir -u URL -w /usr/share/seclists/Discovery/Web-Content/common.txt" "gobuster version"
    Add-Wsl $c "ffuf - Web Fuzzing" "ffuf -u URL/FUZZ -w /usr/share/seclists/Discovery/Web-Content/common.txt" "ffuf -V"
    Add-Cmd $c "SQLmap - SQL Injection" "sqlmap -u http://target/page?id=1 --dbs" "sqlmap --version"
    Add-Dossier $c "Payloads - Payload Library" "$Tools\PayloadsAllTheThings" "https://github.com/swisskyrepo/PayloadsAllTheThings"

    $c = "06-Cryptanalysis${sep}Cryptanalyse"
    Add-Url $c "CyberChef - Data Conversion" "https://gchq.github.io/CyberChef/"
    Add-Url $c "dCode - Classic Ciphers" "https://www.dcode.fr/"
    Add-Dossier $c "RsaCtfTool - Break RSA" "$Tools\RsaCtfTool" "https://github.com/RsaCtfTool/RsaCtfTool"
    Add-Wsl $c "Hashcat - Crack Hashes" "hashcat -m 0 hash.txt /usr/share/wordlists/rockyou.txt" "hashcat --version"
    Add-Wsl $c "John - Crack Passwords" "john --wordlist=/usr/share/wordlists/rockyou.txt hashes.txt" "john | head -n 1"
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

    Write-Host "Shortcuts in: $Racine" -ForegroundColor Green
    if ($manquants) { Write-Host "Missing (a .txt with the download link was created instead): $($manquants -join ', ')" -ForegroundColor Yellow }
    if (-not $distro) { Write-Host "No WSL distro found: Kali shortcuts will not work until Kali is installed (restart, then run the script again)." -ForegroundColor Yellow }
    Start-Process explorer.exe $Racine

    # ---------- Summary ----------
    Write-Host ""
    Write-Host "===== SUMMARY =====" -ForegroundColor Green
    Write-Host "Installed : $($ok -join ', ')"
    Write-Host "Already   : $($deja -join ', ')"
    if ($echec) { Write-Host "Failed    : $($echec -join ', ')" -ForegroundColor Red }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host ""
    Read-Host "Press Enter to close"
}
