# 🏴‍☠️ Le Guide Ultime pour Root-Me

Guide de survie pour [Root-Me](https://www.root-me.org/), pensé pour les débutants sous Windows. Il liste les outils indispensables et les concepts à maîtriser pour chaque catégorie, et fournit un script qui installe tout le kit d'un coup.

Les catégories sont triées de la plus accessible à la plus avancée. Au sein de chaque catégorie, les outils sont ordonnés du plus basique au plus complexe.

**Légende des difficultés :**
*   🟢 **Accessible** (idéal pour débuter)
*   🟡 **Intermédiaire** (demande quelques bases)
*   🔴 **Avancé** (nécessite de solides connaissances techniques)
*   💀 **Extrême** (maîtrise complète de l'architecture requise)

---

## 🚀 Installation rapide (Windows)

1. Télécharge `install_tools.ps1` depuis ce dépôt.
2. Ouvre PowerShell dans le dossier du fichier et lance :
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\install_tools.ps1
   ```
   (un clic droit puis "Exécuter avec PowerShell" fonctionne aussi, le script se relance tout seul en administrateur.)
3. Si le script demande de redémarrer (installation de WSL), redémarre le PC puis relance le script.

**Le script est rejouable à volonté** : il détecte ce qui est déjà installé et ne refait que ce qui manque.

**Ce qu'il met en place :**
*   Programmes Windows via `winget` : Git, Python 3, Java, VS Code, 7-Zip, Audacity, ExifTool, Wireshark, Nmap, Burp Suite CE, x64dbg, VirtualBox.
*   HxD n'est pas installé automatiquement (le serveur de téléchargement est instable) : le script crée un fichier `.txt` avec le lien dans les dossiers Stéganographie et Forensic, et le raccourci apparaît dès que tu l'as installé à la main puis relancé le script.
*   Téléchargements GitHub : Ghidra, Cutter, Autopsy, Stegsolve, CyberChef (version hors ligne), PayloadsAllTheThings, RsaCtfTool, PEASS-ng, Volatility 3, BeEF.
*   Kali Linux sous WSL 2 avec tous les outils Linux (steghide, binwalk, gobuster, ffuf, john, hashcat, gdb avec pwndbg, radare2, sqlmap, Metasploit, wordlists dont `rockyou.txt`, SecLists, pwntools...).
*   Bibliothèques Python : requests, pwntools, beautifulsoup4, scapy, sqlmap, pycryptodome, sympy, pillow.
*   Un dossier `RootMe-Tools\Categories` avec un sous-dossier par catégorie et des raccourcis prêts à l'emploi, plus un dossier `Workspace` où déposer les fichiers des épreuves.

**Option :** SageMath (très lourd, utile pour la crypto avancée) s'active en passant `$InstallSage` à `$true` en haut du script.

> ⚠️ **Smart App Control** (Windows 11) bloque les installeurs non signés comme ExifTool ou x64dbg, et il n'existe aucune exclusion possible. Le script te prévient s'il est actif. Pour continuer, désactive-le dans Sécurité Windows (Contrôle des applications et du navigateur, paramètres de Smart App Control), relance le script, puis réactive-le si ta version de Windows le permet.

> ⚠️ Le dossier `Tools` est exclu de Windows Defender, car des outils comme PEASS-ng ou BeEF sont détectés comme malveillants. Le dossier `Workspace` n'est volontairement **pas** exclu : n'ouvre jamais un fichier d'épreuve douteux directement sur ta machine si tu n'es pas sûr de toi, utilise plutôt WSL ou une VM.

---

## ⚠️ Le prérequis absolu pour Windows

La majorité des outils de hacking sont pensés pour Linux. Sous Windows, tu as besoin de l'un de ces environnements :
*   **[WSL 2 (Windows Subsystem for Linux)](https://learn.microsoft.com/fr-fr/windows/wsl/install)** avec Kali Linux ou Ubuntu. *Recommandé : léger, s'intègre bien à Windows. C'est ce que configure le script.*
*   *Ou* **une machine virtuelle** via [VirtualBox](https://www.virtualbox.org/) avec l'ISO de [Kali Linux](https://www.kali.org/get-kali/#kali-virtual-machines).

---

## 🗺️ Ordre conseillé pour débuter

1. **Bases de Linux** dans WSL (`ls`, `cd`, `cat`, `grep`, `find`, droits des fichiers). C'est ce qui bloque le plus de débutants.
2. **Stéganographie** et **Web Client** : rapides, très visuels, bonne mise en confiance.
3. **Programmation** : Python te servira dans presque toutes les catégories suivantes.
4. **Réseau**, puis **Web Serveur**.
5. **Cryptanalyse** et **App Script**.
6. **Forensic**, puis **Cracking**, **App Système** et **Réaliste** quand tu es à l'aise avec l'assembleur et la mémoire.

---

## 🖼️ 1. Stéganographie (24 épreuves) 🟢
*Trouver des données cachées. L'art de la dissimulation, idéal pour se familiariser avec la fouille de fichiers.*

*   **Outils :**
    *   **[ExifTool](https://exiftool.org/) :** première étape obligatoire. Lit les métadonnées (texte caché) d'une image ou d'un fichier.
    *   **[HxD](https://mh-nexus.de/en/hxd/) :** éditeur hexadécimal pour vérifier les magic bytes et repérer des données ajoutées en fin de fichier.
    *   **[Stegsolve](http://www.caesum.com/handbook/Stegsolve.jar) :** outil visuel Java pour observer les différents plans de couleurs (bit de poids faible).
    *   **[Steghide](https://steghide.sourceforge.net/) :** extrait des données cachées *protégées par un mot de passe* dans des JPEG ou de l'audio.
    *   **[Zsteg](https://github.com/zed-0xff/zsteg) :** extrait automatiquement les données LSB des fichiers PNG/BMP.
    *   **[Audacity](https://www.audacityteam.org/) :** pour l'audio, passe en vue spectrogramme pour révéler une image ou du texte caché dans les fréquences.
*   **Concepts à maîtriser :** métadonnées (EXIF), LSB (Least Significant Bit), analyse de spectre audio, magic bytes (en-têtes de fichiers).

## 🌐 2. Web Client (42 épreuves) 🟢 à 🟡
*Attaquer l'utilisateur via son navigateur. Très visuel et très demandé en Bug Bounty.*

*   **Outils :**
    *   **Console de développement (F12) :** l'outil principal. Inspecteur d'éléments pour modifier le HTML, console JS, onglet Network.
    *   **[BeEF](https://beefproject.com/) :** framework d'exploitation de navigateurs, pour tester les XSS.
    *   **[XSS Hunter](https://xsshunter.com/) :** pour les XSS aveugles (Blind XSS). Vérifie que le service est toujours en ligne, sinon utilise une alternative auto-hébergée.
*   **Concepts à maîtriser :** failles XSS (Reflected, Stored, DOM), CSRF (Cross-Site Request Forgery), contournement des CSP (Content Security Policy), requêtes CORS.

## ⚙️ 3. Programmation (29 épreuves) 🟡
*Indispensable pour automatiser les tâches répétitives des autres épreuves.*

*   **Outils / langages :**
    *   **[Python 3](https://www.python.org/downloads/) :** le langage roi du hacking.
    *   **[VS Code](https://code.visualstudio.com/) :** éditeur pour écrire tes scripts.
    *   **Bibliothèques Python :** `requests` (web), `pwntools` / `socket` (réseau), `BeautifulSoup` (parsing HTML), `pycryptodome` (crypto).
    *   **CyberChef (copie hors ligne, installée par le script) :** pour tester rapidement une chaîne de conversions avant de la coder. Raccourci dans `03-Programmation` et `06-Cryptanalyse`.
*   **Concepts à maîtriser :** manipulation de chaînes (Base64, hexadécimal), boucles rapides, lecture de flux réseau (sockets), limites de temps des épreuves (le script doit répondre vite).

## 📡 4. Réseau (35 épreuves) 🟡
*Comprendre comment les machines discutent entre elles et intercepter leurs communications.*

*   **Outils :**
    *   **[Wireshark](https://www.wireshark.org/) :** analyseur visuel de captures de paquets `.pcap`.
    *   **[Nmap](https://nmap.org/) :** scanner de ports pour découvrir les services actifs.
    *   **Netcat (`nc`) :** le couteau suisse TCP/UDP (indispensable pour les reverse shells).
    *   **Scapy (Python) :** bibliothèque pour forger des paquets réseau personnalisés de A à Z. Raccourci `Scapy - Packet Forging` pour le shell interactif.
    *   **Scapy - Decode Hex Frame (raccourci dédié) :** pour les épreuves où Root-Me donne juste un bloc hexadécimal brut d'une trame (`00 05 73 a0 ...`). Le raccourci vérifie et installe `python3-scapy` tout seul si besoin (en root via `wsl -u root`, donc sans jamais demander le mot de passe de l'utilisateur Linux), puis tu colles le hex, ligne vide ou Ctrl+D → toutes les couches (Ethernet, IP/IPv6, TCP/UDP, payload HTTP/FTP/Telnet...) sont décodées et affichées automatiquement.
*   **Concepts à maîtriser :** modèle OSI, poignée de main TCP (handshake), requêtes ARP/DNS, protocoles non chiffrés (Telnet, FTP, HTTP).

## 🌐 5. Web Serveur (97 épreuves) 🟡 à 🔴
*Le cœur du métier. Comprendre comment attaquer l'infrastructure back-end et les bases de données.*

*   **Outils :**
    *   **[Burp Suite Community](https://portswigger.net/burp/communitydownload) :** le proxy indispensable pour intercepter, stopper et modifier les requêtes HTTP.
    *   **[Gobuster](https://github.com/OJ/gobuster) / [ffuf](https://github.com/ffuf/ffuf) :** découvrent les fichiers et dossiers cachés d'un serveur (fuzzing). Wordlists dans [SecLists](https://github.com/danielmiessler/SecLists).
    *   **[SQLmap](https://sqlmap.org/) :** exploitation automatisée des failles SQL (à utiliser une fois la faille comprise).
*   **Concepts à maîtriser :** injection SQL (SQLi), LFI/RFI (inclusion de fichiers locaux/distants), SSRF, injection de commandes, upload de fichiers malveillants.
*   **Ressource vitale :** [PayloadsAllTheThings](https://github.com/swisskyrepo/PayloadsAllTheThings) (la bible des payloads).

## 🔐 6. Cryptanalyse (75 épreuves) 🟡 à 🔴
*Casser des algorithmes de chiffrement et retrouver des mots de passe.*

*   **Outils :**
    *   **[dCode.fr](https://www.dcode.fr/) :** en ligne, pour identifier et résoudre les chiffres historiques (César, Vigenère) et mathématiques.
    *   **CyberChef (copie hors ligne)** : le couteau suisse pour enchaîner les conversions (Base64, Hex, XOR...).
    *   **[RsaCtfTool](https://github.com/RsaCtfTool/RsaCtfTool) :** script Python pour attaquer des clés RSA mal générées ou faibles.
    *   **[Hashcat](https://hashcat.net/hashcat/) / [John the Ripper](https://www.openwall.com/john/) :** craquent des condensats (hashes) avec la célèbre wordlist `rockyou.txt` (dans `/usr/share/wordlists/` sous Kali).
        ```bash
        # Exemple avec un hash MD5 (ici celui d'une chaîne vide) :
        echo 31d6cfe0d16ae931b73c59d7e0c089c0 > hash.txt

        hashcat -m 0 hash.txt /usr/share/wordlists/rockyou.txt   # -m 0 = MD5, -m 1000 = NTLM, -m 100 = SHA1...
        hashcat -m 0 hash.txt --show                              # réaffiche le résultat déjà cassé

        john --format=raw-md5 --wordlist=/usr/share/wordlists/rockyou.txt hash.txt
        john --show hash.txt                                      # réaffiche le résultat déjà cassé

        rm hash.txt   # nettoyage une fois fini
        ```
        Le résultat cassé reste aussi en cache (potfile) même après `rm hash.txt` : `~/.hashcat/hashcat.potfile` pour Hashcat, `~/.john/john.pot` pour John. Supprime-les aussi si tu veux repartir de zéro sur le même hash.
        Les raccourcis `Hashcat - Crack Hashes` et `John - Crack Passwords` (dossier `06-Cryptanalyse`) affichent ces commandes au démarrage du terminal Kali.
    *   **[SageMath](https://www.sagemath.org/) :** pour les épreuves RSA et courbes elliptiques avancées (installation optionnelle, lourde).
*   **Concepts à maîtriser :** chiffrement asymétrique (RSA), symétrique (AES ECB vs CBC), opérations XOR, fonctions de hachage (MD5, SHA).

## 💻 7. App Script (33 épreuves) 🟡 à 🔴
*L'art de l'escalade de privilèges (PrivEsc) via des erreurs de configuration système.*

*   **Outils :**
    *   **Terminal Linux (Bash) :** maîtrise `find`, `grep`, `sudo -l`, `cat /etc/passwd`.
    *   **[PEASS-ng (LinPEAS / WinPEAS)](https://github.com/peass-ng/PEASS-ng) :** scripts automatisés qui listent les failles de configuration d'une machine.
*   **Concepts à maîtriser :** droits SUID/SGID, variables d'environnement, tâches planifiées (cron), PATH hijacking.
*   **Ressource vitale :** [GTFOBins](https://gtfobins.github.io/) (pour exploiter des binaires système mal configurés).

## 🕵️ 8. Forensic (48 épreuves) 🔴
*Investigation numérique : analyser des traces mémoire, des disques durs ou des fichiers corrompus.*

*   **Outils :**
    *   **`strings` (commande Linux) :** la base absolue. Extrait tout le texte lisible d'un fichier binaire.
    *   **[HxD](https://mh-nexus.de/en/hxd/) :** pour inspecter et réparer des en-têtes de fichiers corrompus.
    *   **[Binwalk](https://github.com/ReFirmLabs/binwalk) / Foremost :** extraient des fichiers (archives, images, firmware) cachés à l'intérieur d'autres fichiers.
    *   **[Autopsy](https://www.autopsy.com/download/) :** interface graphique pour l'analyse forensique de systèmes de fichiers (disques durs).
    *   **[Volatility 3](https://github.com/volatilityfoundation/volatility3) :** framework pour analyser les dumps de mémoire vive (RAM) et retrouver processus, mots de passe ou malwares.
*   **Concepts à maîtriser :** architecture des systèmes de fichiers, gestion de la mémoire vive (RAM), récupération de données supprimées, analyse de malwares.

## 🧠 9. Cracking (70 épreuves) 🔴 à 💀
*Comprendre les langages compilés et faire de la rétro-ingénierie (reverse engineering).*

*   **Outils :**
    *   **`strace` / `ltrace` :** sous Linux, observent les appels système et les fonctions appelées par un programme en temps réel.
    *   **[Ghidra](https://ghidra-sre.org/) :** décompilateur de la NSA (transforme l'assembleur en pseudo-code C lisible).
    *   **[Cutter](https://cutter.re/) / [Radare2](https://rada.re/) :** alternative gratuite et open source à IDA, Cutter étant l'interface graphique de Radare2.
    *   **[x64dbg](https://x64dbg.com/) :** débogueur Windows de référence.
    *   **[IDA Free](https://hex-rays.com/ida-free/) :** standard de l'industrie pour le désassemblage interactif (compte Hex-Rays gratuit requis).
*   **Concepts à maîtriser :** langage assembleur (x86/x64), registres CPU, sauts conditionnels (JMP, JE, JNE), patching de binaires.

## 🛠️ 10. App Système (93 épreuves) 💀
*Trouver et exploiter des failles de programmation (souvent C/C++) directement dans la mémoire de l'ordinateur.*

*   **Outils :**
    *   **[GDB](https://www.gnu.org/software/gdb/) avec [pwndbg](https://github.com/pwndbg/pwndbg) :** le débogueur Linux. pwndbg (ou [GEF](https://github.com/hugsy/gef)) est obligatoire pour avoir une vue claire de la mémoire et des registres. Le script installe pwndbg.
    *   **[Pwntools](https://github.com/Gallopsled/pwntools) (Python) :** indispensable pour crafter le payload avec précision et interagir avec le binaire. À utiliser dans WSL plutôt que sous Windows.
*   **Concepts à maîtriser :** buffer overflow (BoF), ROP (Return Oriented Programming), format string, contournement des protections mémoire (ASLR, NX bit, canary).

## 🌍 11. Réaliste (62 épreuves) 💀
*Le boss final. Tu es confronté à des architectures complètes et des scénarios réels.*

*   **Outils :**
    *   Ici, c'est l'examen final : tu combines tout ton arsenal précédent.
    *   **[Metasploit](https://www.metasploit.com/) :** utile pour exploiter rapidement des failles très connues.
    *   **[Searchsploit](https://www.exploit-db.com/searchsploit) :** cherche des exploits publics hors ligne en ligne de commande.
*   **Concepts à maîtriser (méthodologie complète) :**
    1. Reconnaissance et énumération.
    2. Accès initial (foothold, souvent via le Web).
    3. Élévation de privilèges (PrivEsc, App Script).
    4. Découverte du réseau interne (pivoting).

---

## 📚 Ressources pour aller plus loin

*   **[awesome-ctf](https://github.com/apsdehal/awesome-ctf) :** liste de référence par catégorie, avec outils, writeups et plateformes d'entraînement.
*   **[ctf-katana](https://github.com/JohnHammond/ctf-katana) :** aide-mémoire de commandes par catégorie, pratique pendant une épreuve.
*   **[zardus/ctf-tools](https://github.com/zardus/ctf-tools) :** installeur d'outils pour Linux (à utiliser dans WSL ou une VM, pas sous Windows directement). Assez ancien, certains outils peuvent échouer.

Vérifie toujours la date des derniers commits d'un dépôt avant de t'y fier.
