# 🏴‍☠️ Le Guide Ultime pour Root-Me

Bienvenue dans ce guide de survie pour [Root-Me](https://www.root-me.org/), pensé pour les débutants. Ce document liste les outils indispensables et les concepts à maîtriser pour chaque catégorie. 

Les catégories sont triées de la plus accessible à la plus avancée. Au sein de chaque catégorie, les outils sont ordonnés du plus basique au plus complexe.

**Légende des difficultés :**
*   🟢 **Accessible** (Idéal pour débuter)
*   🟡 **Intermédiaire** (Demande quelques bases)
*   🔴 **Avancé** (Nécessite de solides connaissances techniques)
*   💀 **Extrême** (Maîtrise complète de l'architecture requise)

> **🚀 Astuce d'installation rapide (Windows) :** 
> Téléchargez le script `install_tools.ps1` de ce dépôt, faites un clic droit dessus et sélectionnez "Exécuter avec PowerShell" pour installer automatiquement les outils de base !

---

## ⚠️ Le Prérequis Absolu pour Windows

La majorité des outils de hacking sont pensés pour Linux. Sous Windows, vous devez absolument installer l'un de ces environnements :
*   **[WSL 2 (Windows Subsystem for Linux)](https://learn.microsoft.com/fr-fr/windows/wsl/install)** avec Kali Linux ou Ubuntu. *Recommandé : léger, s'intègre parfaitement à Windows.*
*   *Ou* **Une Machine Virtuelle** via [VirtualBox](https://www.virtualbox.org/) avec l'ISO de [Kali Linux](https://www.kali.org/get-kali/#kali-virtual-machines).

---

## 🖼️ 1. Stéganographie (24 épreuves) - 🟢
*Trouver des données cachées. L'art de la dissimulation, idéal pour se familiariser avec la fouille de fichiers.*

*   **Outils :**
    *   **[ExifTool](https://exiftool.org/) :** Première étape obligatoire. Lit les métadonnées (texte caché) d'une image ou d'un fichier.
    *   **[Stegsolve](https://github.com/zardus/ctf-tools/blob/master/stegsolve/install) :** Outil visuel Java pour observer les différents plans de couleurs (Bit de Poids Faible).
    *   **[Steghide](https://steghide.sourceforge.net/) :** Pour extraire des données cachées *protégées par un mot de passe* dans des JPEG ou de l'audio.
    *   **[Zsteg](https://github.com/zed-0xff/zsteg) :** L'outil avancé pour extraire automatiquement les données LSB des fichiers PNG/BMP.
*   **Concepts à maîtriser :** Métadonnées (EXIF), LSB (Least Significant Bit), Analyse de spectre audio, Magic Bytes (En-têtes de fichiers).

## 🌐 2. Web - Client (42 épreuves) - 🟢 à 🟡
*Attaquer l'utilisateur via son navigateur. Très visuel et très demandé en Bug Bounty.*

*   **Outils :**
    *   **Console de développement (F12) :** L'outil principal ! Inspecteur d'éléments pour modifier le HTML, Console JS, Network.
    *   **[XSS Hunter](https://xsshunter.com/) / [BeEF](https://beefproject.com/) :** Pour tester et exploiter les failles XSS, notamment à l'aveugle (Blind XSS).
*   **Concepts à maîtriser :** Failles XSS (Reflected, Stored, DOM), CSRF (Cross-Site Request Forgery), contournement des CSP (Content Security Policy), requêtes CORS.

## ⚙️ 3. Programmation (29 épreuves) - 🟡
*Indispensable pour automatiser les tâches répétitives des autres épreuves.*

*   **Outils / Langages :**
    *   **[Python 3](https://www.python.org/downloads/) :** Le langage roi absolu du hacking.
    *   **Bibliothèques Python :** `requests` (interactions web), `pwntools` / `socket` (interactions réseau), `BeautifulSoup` (parsing HTML).
*   **Concepts à maîtriser :** Manipulation de chaînes de caractères (Base64, Hexadécimal), écriture de boucles rapides, lecture de flux réseau (sockets).

## 📡 4. Réseau (35 épreuves) - 🟡
*Comprendre comment les machines discutent entre elles et intercepter leurs communications.*

*   **Outils :**
    *   **[Wireshark](https://www.wireshark.org/) :** L'analyseur visuel de captures de paquets `.pcap`.
    *   **[Nmap](https://nmap.org/) :** Scanner de ports pour découvrir les services actifs.
    *   **Netcat (`nc`) :** Le couteau suisse TCP/UDP (indispensable pour les "Reverse Shells").
    *   **Scapy (Python) :** Bibliothèque puissante pour forger des paquets réseau personnalisés de A à Z.
*   **Concepts à maîtriser :** Modèle OSI, poignée de main TCP (Handshake), requêtes ARP/DNS, protocoles non chiffrés (Telnet, FTP, HTTP).

## 🌐 5. Web - Serveur (97 épreuves) - 🟡 à 🔴
*Le cœur du métier. Comprendre comment attaquer l'infrastructure back-end et les bases de données.*

*   **Outils :**
    *   **[Burp Suite Community](https://portswigger.net/burp/communitydownload) :** Le proxy indispensable pour intercepter, stopper et modifier les requêtes HTTP.
    *   **[Gobuster](https://github.com/OJ/gobuster) / [ffuf](https://github.com/ffuf/ffuf) :** Pour découvrir les fichiers et dossiers cachés sur un serveur (fuzzing).
    *   **[SQLmap](https://sqlmap.org/) :** Exploitation automatisée des failles SQL (à utiliser quand on a compris la faille).
*   **Concepts à maîtriser :** SQL Injection (SQLi), LFI/RFI (Inclusion de fichiers locaux/distants), SSRF, Command Injection, Upload de fichiers malveillants.
*   **Ressource vitale :** [PayloadsAllTheThings](https://github.com/swisskyrepo/PayloadsAllTheThings) (La bible des payloads).

## 🔐 6. Cryptanalyse (75 épreuves) - 🟡 à 🔴
*Casser des algorithmes de chiffrement et retrouver des mots de passe.*

*   **Outils :**
    *   **[dCode.fr](https://www.dcode.fr/) :** (En ligne) Pour identifier et résoudre les chiffres historiques (César, Vigenère) et mathématiques.
    *   **[CyberChef](https://gchq.github.io/CyberChef/) :** Le couteau suisse (hors-ligne/en ligne) pour enchaîner les conversions (Base64 -> Hex -> XOR).
    *   **[RsaCtfTool](https://github.com/RsaCtfTool/RsaCtfTool) :** Script Python magique pour attaquer des clés RSA mal générées ou faibles.
    *   **[Hashcat](https://hashcat.net/hashcat/) / John The Ripper :** Pour craquer des condensats (hashes) en force brute avec la célèbre wordlist `rockyou.txt`.
*   **Concepts à maîtriser :** Chiffrement asymétrique (RSA), symétrique (AES ECB vs CBC), opérations XOR, fonctions de hachage (MD5, SHA).

## 💻 7. App - Script (33 épreuves) - 🟡 à 🔴
*L'art de l'escalade de privilèges (PrivEsc) via des erreurs de configuration système.*

*   **Outils :**
    *   **Terminal Linux (Bash) :** Maîtriser `find`, `grep`, `sudo -l`, `cat /etc/passwd`.
    *   **[PEASS-ng (LinPEAS / WinPEAS)](https://github.com/peass-ng/PEASS-ng) :** Scripts automatisés pour lister toutes les failles de configuration d'une machine.
*   **Concepts à maîtriser :** Droits SUID/SGID, variables d'environnement, tâches planifiées (Cron), PATH hijacking.
*   **Ressource vitale :** [GTFOBins](https://gtfobins.github.io/) (pour exploiter des binaires système classiques mal configurés).

## 🕵️ 8. Forensic (48 épreuves) - 🔴
*Investigation numérique : analyser des traces mémoire, des disques durs ou des fichiers corrompus.*

*   **Outils :**
    *   **`strings` (Commande Linux) :** La base absolue. Extrait tout le texte lisible d'un fichier binaire.
    *   **[Binwalk](https://github.com/ReFirmLabs/binwalk) / Foremost :** Pour extraire des fichiers (archives, images, firmware) cachés à l'intérieur d'autres fichiers.
    *   **[Autopsy](https://www.autopsy.com/download/) :** Interface graphique pour l'analyse forensique de systèmes de fichiers (disques durs).
    *   **[Volatility (v2/v3)](https://github.com/volatilityfoundation/volatility3) :** Le framework ultime pour analyser les dumps de mémoire vive (RAM) et retrouver processus, mots de passe ou malwares.
*   **Concepts à maîtriser :** Architecture des systèmes de fichiers, gestion de la mémoire vive (RAM), récupération de données supprimées, analyse de malwares.

## 🧠 9. Cracking (70 épreuves) - 🔴 à 💀
*Comprendre les langages compilés et faire de la rétro-ingénierie (Reverse Engineering).*

*   **Outils :**
    *   **`strace` / `ltrace` :** Sous Linux, pour observer les appels système et les fonctions appelées par un programme en temps réel.
    *   **[Ghidra](https://ghidra-sre.org/) :** Le puissant décompilateur de la NSA (transforme l'assembleur complexe en pseudo-code C compréhensible).
    *   **[x64dbg](https://x64dbg.com/) :** Débogueur Windows de référence.
    *   **[IDA Free](https://hex-rays.com/ida-free/) :** Le standard absolu de l'industrie pour le désassemblage interactif.
*   **Concepts à maîtriser :** Langage Assembleur (x86/x64), gestion des registres CPU, sauts conditionnels (JMP, JE, JNE), patching de binaires.

## 🛠️ 10. App - Système (93 épreuves) - 💀
*Trouver et exploiter des failles de programmation (souvent C/C++) directement dans la mémoire de l'ordinateur.*

*   **Outils :**
    *   **[GDB](https://www.gnu.org/software/gdb/) (avec plugins [GEF](https://github.com/hugsy/gef) ou [PEDA]) :** Le débogueur Linux. GEF/PEDA sont obligatoires pour avoir une vue claire de la mémoire et des registres.
    *   **Pwntools (Python) :** Indispensable pour crafter le payload malveillant avec précision et interagir avec le binaire.
*   **Concepts à maîtriser :** Buffer Overflow (Bof), ROP (Return Oriented Programming), failles Format String, contournement des protections mémoire (ASLR, NX bit, Canary).

## 🌍 11. Réaliste (62 épreuves) - 💀
*Le boss final. Vous êtes confrontés à des architectures complètes et des scénarios réels.*

*   **Outils :**
    *   Ici, c'est l'examen final : vous combinez tout votre arsenal précédent.
    *   **[Metasploit](https://www.metasploit.com/) :** Parfois toléré/utile pour exploiter rapidement des failles très connues.
    *   **[Searchsploit](https://www.exploit-db.com/searchsploit) :** Outil en ligne de commande pour chercher des exploits publics hors-ligne.
*   **Concepts à maîtriser (Méthodologie Complète) :** 
    1. Reconnaissance & Énumération.
    2. Accès Initial (Foothold / Web).
    3. Élévation de privilèges (PrivEsc / App-Script).
    4. Découverte du réseau interne (Pivoting).
