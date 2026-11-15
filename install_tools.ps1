# ==========================================================
#  Root-Me tools: install (skips what is already installed)
#  + one folder per category with shortcuts
#
#  Run from a PowerShell window:
#    Set-ExecutionPolicy -Scope Process Bypass -Force
#    .\install_tools.ps1
# ==========================================================

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

    $wslExe = "$env:windir\System32\wsl.exe"
    $psExe  = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    $ok = @(); $deja = @(); $echec = @()

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

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget not found. Install 'App Installer' from the Microsoft Store."
    }

    # ---------- 1. winget programs ----------
    $apps = @(
        @{ Nom = "Git";           Id = "Git.Git";                         Cmd = "git" },
        @{ Nom = "Python 3";      Id = "Python.Python.3.12";              Cmd = "python" },
        @{ Nom = "Java";          Id = "Microsoft.OpenJDK.21";            Cmd = "java" },
        @{ Nom = "ExifTool";      Id = "OliverBetz.ExifTool";             Cmd = "exiftool" },
        @{ Nom = "Wireshark";     Id = "WiresharkFoundation.Wireshark";   Cmd = "" },
        @{ Nom = "Nmap";          Id = "Insecure.Nmap";                   Cmd = "nmap" },
        @{ Nom = "Burp Suite CE"; Id = "PortSwigger.BurpSuite.Community"; Cmd = "" },
        @{ Nom = "x64dbg";        Id = "x64dbg.x64dbg";                   Cmd = "" },
        @{ Nom = "VirtualBox";    Id = "Oracle.VirtualBox";               Cmd = "" }
    )
    foreach ($a in $apps) {
        $present = $false
        if ($a.Cmd -and (Get-Command $a.Cmd -ErrorAction SilentlyContinue)) { $present = $true }
        if (-not $present) {
            winget list --id $a.Id --exact --accept-source-agreements *> $null
            if ($LASTEXITCODE -eq 0) { $present = $true }
        }
        if ($present) { Write-Host "[already installed] $($a.Nom)" -ForegroundColor Yellow; $deja += $a.Nom; continue }
        Write-Host "[installing] $($a.Nom)..." -ForegroundColor Cyan
        winget install --id $a.Id --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) { $ok += $a.Nom } else { $echec += $a.Nom }
    }

    # ---------- 2. WSL: Kali + Linux tools ----------
    $distro = Get-Distro
    if ($distro -like "kali*") {
        Write-Host "[already installed] Kali ($distro)" -ForegroundColor Yellow; $deja += "Kali"
    } else {
        Write-Host "[installing] Kali (WSL)..." -ForegroundColor Cyan
        wsl --install -d kali-linux --no-launch
        $distro = Get-Distro
        if ($distro -like "kali*") { $ok += "Kali" } else { $echec += "Kali (restart the PC, then run this script again)" }
    }
    if ($distro -like "kali*") {
        Write-Host "[installing] Linux tools in Kali (apt, can take a while)..." -ForegroundColor Cyan
        $sh = "$Tools\setup_kali.sh"
        $lines = @(
            "export DEBIAN_FRONTEND=noninteractive",
            "apt-get update -y",
            "apt-get install -y steghide binwalk foremost gobuster ffuf john hashcat gdb ltrace strace netcat-traditional exploitdb metasploit-framework ruby-dev build-essential",
            "gem install zsteg"
        )
        [IO.File]::WriteAllText($sh, (($lines -join "`n") + "`n"))
        $shWsl = "/mnt/" + $sh.Substring(0,1).ToLower() + $sh.Substring(2).Replace("\", "/")
        & $wslExe -d $distro -u root -- bash $shWsl
        if ($LASTEXITCODE -eq 0) { $ok += "Kali Linux tools" } else { $echec += "Kali Linux tools (run setup_kali.sh again)" }
    }

    # ---------- 3. Python libraries ----------
    $env:Path = $env:Path + ";" + [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $installed = (python -m pip list --format=freeze 2>$null) -replace "==.*", ""
        foreach ($p in "requests","pwntools","beautifulsoup4","scapy","sqlmap") {
            if ($installed -contains $p) { Write-Host "[already installed] pip $p" -ForegroundColor Yellow; $deja += "pip $p" }
            else { Write-Host "[pip] $p..." -ForegroundColor Cyan; python -m pip install $p; $ok += "pip $p" }
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
    Write-Host "[downloading] Stegsolve..." -ForegroundColor Cyan
    $got = (Get-File "http://www.caesum.com/handbook/Stegsolve.jar" "$Tools\stegsolve.jar") -or `
           (Get-File "https://github.com/eugenekolo/sec-tools/raw/master/stego/stegsolve/stegsolve/stegsolve.jar" "$Tools\stegsolve.jar")
    if ($got) { $ok += "Stegsolve" } else { $echec += "Stegsolve" }

    # ---------- 6. Ghidra + Autopsy (GitHub releases) ----------
    Write-Host "[installing] Ghidra (GitHub)..." -ForegroundColor Cyan
    $good = $false
    $rel = Get-Json "https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    if ($asset -and (Get-File $asset.browser_download_url "$Tools\ghidra.zip")) {
        Expand-Archive "$Tools\ghidra.zip" -DestinationPath "$Tools\Ghidra" -Force
        Remove-Item "$Tools\ghidra.zip" -Force
        $good = $true
    }
    if ($good) { $ok += "Ghidra" } else { $echec += "Ghidra" }

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

    # ==========================================================
    #  7. Category folders + shortcuts
    # ==========================================================
    Write-Host ""
    Write-Host "[shortcuts] Building category folders..." -ForegroundColor Cyan

    $sep = " " + [char]0x00A6 + " "     # looks like a pipe (a real | is not allowed in file names)

    # Starter script for the Python shortcut
    Set-Content -Path "$Tools\solve.py" -Encoding ASCII -Value @'
# Root-Me starter script  -  run with:  python ..\Tools\solve.py
import requests
# from pwn import *            # sockets / exploits
# import base64, binascii      # encodings

URL = "http://challenge01.root-me.org/"
r = requests.get(URL)
print(r.status_code)
print(r.text[:500])
'@

    $manquants = @()
    $ws = New-Object -ComObject WScript.Shell
    $distro = Get-Distro
    $dArg = if ($distro) { "-d $distro --" } else { "--" }
    $WorkWsl = "/mnt/" + $Work.Substring(0,1).ToLower() + $Work.Substring(2).Replace("\", "/")
    $startMenus = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")
    $racinesExe = @("$env:LOCALAPPDATA\Microsoft\WinGet\Links", "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "$env:LOCALAPPDATA\Programs", $Dossier)

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

    $c = "00-Prerequisites${sep}Prerequis"
    Add-App $c "VirtualBox - Virtual Machine" "*VirtualBox*" "VirtualBox.exe" "https://www.virtualbox.org/wiki/Downloads" ""
    Add-Wsl $c "Kali - Linux Terminal" "ls then cd to your files" ""

    $c = "01-Steganography${sep}Steganographie"
    Add-Cmd $c "ExifTool - Read Metadata" "exiftool image.jpg" "exiftool -ver"
    if (Test-Path "$Tools\stegsolve.jar") { Add-Cmd $c "Stegsolve - Color Planes" "open your image with File then Open" "java -jar '$Tools\stegsolve.jar'" }
    else { Add-Missing $c "Stegsolve - Color Planes" "https://github.com/zardus/ctf-tools/tree/master/stegsolve" "Save Stegsolve.jar as $Tools\stegsolve.jar (needs Java)." }
    Add-Wsl $c "Steghide - Extract Hidden" "steghide extract -sf image.jpg" "steghide --version"
    Add-Wsl $c "Zsteg - PNG LSB" "zsteg image.png" "zsteg --version"

    $c = "02-Web-Client"
    Add-Url $c "XSS Hunter - Blind XSS" "https://xsshunter.com/"
    Add-Dossier $c "BeEF - Browser Exploitation" "$Tools\BeEF" "https://github.com/beefproject/beef"

    $c = "03-Programming${sep}Programmation"
    Add-Cmd $c "Python - Write Scripts" "edit Tools\solve.py then python ..\Tools\solve.py" "if (Get-Command code -ErrorAction SilentlyContinue) { code '$Tools' '$Tools\solve.py' } else { notepad '$Tools\solve.py' }"
    Add-Cmd $c "Pwntools - Network Scripting" "from pwn import * then remote(host, port)" "pwn version"

    $c = "04-Network${sep}Reseau"
    Add-App $c "Wireshark - Packet Analysis" "*Wireshark*" "Wireshark.exe" "https://www.wireshark.org/download.html" ""
    Add-Cmd $c "Nmap - Port Scan" "nmap -sV -p- target" "nmap --version"
    Add-Wsl $c "Netcat - TCP Connections" "nc host port" "nc -h 2>&1 | head -n 3"
    Add-Cmd $c "Scapy - Packet Forging" "sniff(count=5) then packets.summary()" "scapy"

    $c = "05-Web-Server${sep}Web-Serveur"
    Add-App $c "Burp - HTTP Proxy" "*Burp*" "BurpSuiteCommunity.exe" "https://portswigger.net/burp/communitydownload" ""
    Add-Wsl $c "Gobuster - Hidden Directories" "gobuster dir -u URL -w wordlist.txt" "gobuster version"
    Add-Wsl $c "ffuf - Web Fuzzing" "ffuf -u URL/FUZZ -w wordlist.txt" "ffuf -V"
    Add-Cmd $c "SQLmap - SQL Injection" "sqlmap -u http://target/page?id=1 --dbs" "sqlmap --version"
    Add-Dossier $c "Payloads - Payload Library" "$Tools\PayloadsAllTheThings" "https://github.com/swisskyrepo/PayloadsAllTheThings"

    $c = "06-Cryptanalysis${sep}Cryptanalyse"
    Add-Url $c "CyberChef - Data Conversion" "https://gchq.github.io/CyberChef/"
    Add-Url $c "dCode - Classic Ciphers" "https://www.dcode.fr/"
    Add-Dossier $c "RsaCtfTool - Break RSA" "$Tools\RsaCtfTool" "https://github.com/RsaCtfTool/RsaCtfTool"
    Add-Wsl $c "Hashcat - Crack Hashes" "hashcat -m 0 hash.txt wordlist.txt" "hashcat --version"
    Add-Wsl $c "John - Crack Passwords" "john --wordlist=wordlist.txt hashes.txt" "john | head -n 1"

    $c = "07-App-Script"
    Add-Url $c "GTFOBins - Binary Exploits" "https://gtfobins.github.io/"
    Add-Dossier $c "PEASS - Privilege Escalation" "$Tools\PEASS-ng" "https://github.com/peass-ng/PEASS-ng"
    Add-Wsl $c "Kali - Linux Terminal" "sudo -l then find / -perm -4000 2>/dev/null" ""

    $c = "08-Forensic${sep}Forensique"
    Add-Wsl $c "Strings - Extract Text" "strings -n 8 file" "strings --version | head -n 1"
    Add-Wsl $c "Binwalk - Embedded Files" "binwalk -e file" "binwalk --help | head -n 3"
    Add-Wsl $c "Foremost - File Carving" "foremost -i file -o out" "foremost -V"
    Add-App $c "Autopsy - Disk Analysis" "Autopsy*" "autopsy64.exe" "https://www.autopsy.com/download/" ""
    Add-Dossier $c "Volatility - RAM Analysis" "$Tools\volatility3" "https://github.com/volatilityfoundation/volatility3"

    $c = "09-Cracking${sep}Retro-ingenierie"
    Add-Wsl $c "Strace - Syscall Tracing" "strace ./binary" "strace -V | head -n 1"
    Add-Wsl $c "Ltrace - Library Calls" "ltrace ./binary" "ltrace -V | head -n 1"
    Add-App $c "Ghidra - Decompile Code" "*Ghidra*" "ghidraRun.bat" "https://github.com/NationalSecurityAgency/ghidra/releases/latest" "Unzip it, then run ghidraRun.bat (needs Java 21)."
    Add-App $c "x64dbg - Windows Debugger" "*x64dbg*" "x96dbg.exe" "https://github.com/x64dbg/x64dbg/releases/latest" ""
    Add-App $c "IDA - Disassemble Code" "IDA Free*" "ida.exe" "https://hex-rays.com/ida-free" "Free Hex-Rays account required: download and install it yourself."

    $c = "10-App-System${sep}App-Systeme"
    Add-Wsl $c "GDB - Linux Debugger" "gdb ./binary then run" "gdb --version | head -n 1"
    Add-Cmd $c "Pwntools - Exploit Crafting" "pwn checksec ./binary" "pwn version"

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
