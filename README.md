# RickyRecon

> RickyRecon is an interactive, menu-driven reconnaissance and enumeration framework built for penetration testers. Designed with OSCP-level engagements in mind, it consolidates 30+ industry-standard tools into a single organized workflow — from initial port scanning through to Active Directory exploitation — all launched in dedicated terminal windows with clean, structured output.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Menus & Tools](#menus--tools)
  - [Port Scanning](#port-scanning)
  - [SNMP Enumeration](#snmp-enumeration)
  - [Web Scanning](#web-scanning)
  - [Directory Fuzzing](#directory-fuzzing)
  - [DNS & OSINT](#dns--osint)
  - [SMB Enumeration](#smb-enumeration)
  - [Active Directory / Kerberos](#active-directory--kerberos)
  - [Brute Force](#brute-force)
  - [Utilities](#utilities)
- [Alternate Port Configuration](#alternate-port-configuration)
- [Output Structure](#output-structure)
- [Disclaimer](#disclaimer)

---

## Features

- **Interactive menu system** — categorized submenus for every phase of enumeration with individual tool options and "Run ALL" batch launchers per category
- **Automated setup** — checks for and installs all required dependencies on first run; configures SNMP MIBs automatically and silently once complete
- **Dedicated terminal windows** — every tool launches in its own terminal displaying the exact command being run before execution
- **Structured output** — all results written to a `recon_reports_<hostname>/` directory, named by tool and target
- **Alt port support** — web scanning and directory fuzzing tools automatically repeat across any additional ports you configure (8080, 8443, etc.)
- **Built-in guidance** — SNMP and AD exploitation options display contextual notes before running, explaining what to look for and recommended next steps
- **Quick scan options** — launch full-recon batches or lightweight quick scans directly from the main menu

---

## Requirements

- Kali Linux or any Debian-based distribution
- `sudo` privileges (required for Nmap, Responder, and tool installation)
- Internet access on first run (for tool installation and SNMP MIB download)

RickyRecon will automatically check for all required tools on startup and prompt to install any that are missing via `apt`.

---

## Installation

```bash
git clone https://github.com/BushidoCyb3r/rickyrecon.git
cd rickyrecon
chmod +x rickyrecon.sh
```

---

## Usage

```bash
cd <target-box-name>
./rickyrecon.sh
```

> The working directory should be named after your target box. RickyRecon uses it for context and confirms this before proceeding.

**On first run you will be prompted to:**
1. Confirm your working directory is named after the target
2. Confirm the target IP has been added to `/etc/hosts`
3. Enter the target host or URL (e.g. `10.10.10.1` or `https://target.htb`)
4. Install any missing tools (single prompt, installs all at once)

**Main menu quick actions:**

| Option | Action |
|--------|--------|
| `9` | Run ALL tools (full recon) |
| `10` | Quick scan — RustScan + WhatWeb + Gobuster |
| `11` | RustScan only |
| `12` | Nuclei only |

---

## Menus & Tools

### Port Scanning

| # | Tool | Description |
|---|------|-------------|
| 1 | RustScan | Fast initial port discovery |
| 2 | Nmap TCP | Full `-p-` scan with service detection and vuln scripts |
| 3 | Nmap UDP | Top 1000 UDP ports with service detection |
| 4 | SNMP Enumeration | Dedicated SNMP submenu (see below) |

**Option A** runs RustScan, Nmap TCP, Nmap UDP, and Nmap SNMP in parallel.

---

### SNMP Enumeration

Accessible via **Port Scanning > Option 4**. SNMP port is configurable (default: 161, press `P` to change).

Passive tools (1–8) are included in the **Run ALL** batch. Exploitation options (9–10) require manual invocation due to required user input.

| # | Tool | Description |
|---|------|-------------|
| 1 | Nmap SNMP | Runs scripts: `snmp-info`, `snmp-brute`, `snmp-sysdescr`, `snmp-processes`, `snmp-netstat`, `snmp-interfaces` |
| 2 | OneSixtyOne | Community string brute force using SecLists SNMP wordlist |
| 3 | SNMPWalk (public) | Full MIB walk with `public` community string |
| 4 | SNMPWalk (private) | Full MIB walk with `private` community string |
| 5 | SNMP-Check | Structured SNMP device enumerator — outputs users, processes, network interfaces, routing table, and more |
| 6 | SNMPWalk Extend | Walks `NET-SNMP-EXTEND-MIB::nsExtendObjects` — reveals configured exec scripts, their commands, arguments, and live output. Common source of credentials and RCE vectors |
| 7 | SNMPWalk UCD Exec | Walks `UCD-SNMP-MIB::extTable` — targets the older `exec` directive in `snmpd.conf`, separate OID tree from Extend |
| 8 | SNMPv3 User Enum | Enumerates valid SNMPv3 usernames by differentiating `unknownEngineID` (valid user) from `unknownUserName` (invalid user) responses |
| 9 | SNMP Write RCE | Prompts for write community string and command to execute. Injects a new `nsExtendObjects` entry via `snmpset`, then reads back output via `nsExtendOutput`. Confirms RCE if write access exists. Prints cleanup command on screen |
| 10 | DISMAN Enum | Walks `mteTriggerTable`, `mteEventTable`, and `mteObjectsTable` — enumerates scheduled automation tasks that may indicate writable RCE via DISMAN-EVENT-MIB |

**Recommended SNMP workflow:**
1. Run OneSixtyOne (2) to find valid community strings
2. Run SNMPWalk public/private (3, 4) and SNMP-Check (5) for full enumeration
3. Run Extend (6) and UCD Exec (7) for exec-mechanism enumeration
4. If a write community string is found, use SNMP Write RCE (9) to attempt command execution

---

### Web Scanning

All tools automatically repeat on any configured alternate ports.

| # | Tool | Description |
|---|------|-------------|
| 1 | Nikto | Web server misconfiguration and vulnerability scanner |
| 2 | Wapiti | Crawl-based web vulnerability scanner (OWASP Top 10, XXE, CSRF) |
| 3 | WhatWeb | Technology fingerprinting — CMS, frameworks, headers, plugins |
| 4 | Nuclei | Template-based scanner — CVEs, misconfigurations (low/med/high/critical) |
| 5 | WPScan | WordPress enumeration — plugins, themes, users, vulnerabilities |
| 6 | Wafw00f | WAF detection and fingerprinting |
| 7 | Arjun | Hidden HTTP parameter discovery — GET, POST, JSON |

**Option A** runs all web scanning tools against the primary target and all configured alt ports.

---

### Directory Fuzzing

All tools automatically repeat on any configured alternate ports.

| # | Tool | Description |
|---|------|-------------|
| 1 | Dirb | Classic directory brute force using default wordlists |
| 2 | Gobuster | Fast directory/file enumeration using `dirb/big.txt` |
| 3 | DirSearch | Web path scanner with extension detection |
| 4 | FFuF | High-speed fuzzer — 50 threads, filters 200/204/301/302/307/401/403 |
| 5 | Feroxbuster | Recursive content discovery with PHP/TXT/HTML extension scanning |

**Option A** runs all fuzzing tools against the primary target and all configured alt ports.

---

### DNS & OSINT

| # | Tool | Description |
|---|------|-------------|
| 1 | DNSRecon | DNS brute force and zone transfer enumeration |
| 2 | FFuF Subdomains | Subdomain brute force using SecLists top-5000 DNS wordlist |
| 3 | Amass | Deep passive and active subdomain enumeration |
| 4 | Subfinder | Fast passive subdomain discovery from multiple OSINT sources |
| 5 | theHarvester | Email, name, and subdomain harvesting from Google, Bing, LinkedIn, GitHub, and more |

---

### SMB Enumeration

| # | Tool | Description |
|---|------|-------------|
| 1 | Enum4linux-ng | Full SMB/RPC enumeration — shares, users, groups, domain info, password policy |
| 2 | NetExec (nxc) | Interactive multi-protocol credential testing and enumeration |

**NetExec supports the following protocols:**
`smb` · `ldap` · `winrm` · `rdp` · `ssh` · `mssql` · `ftp` · `vnc` · `wmi`

**Authentication methods:** Password · NTLM Hash · Kerberos · Null session

**Common flags (prompted interactively via extra options):**

| Flag | Description |
|------|-------------|
| `--shares` | Enumerate SMB shares |
| `--users` | Enumerate users |
| `--groups` | Enumerate groups |
| `--pass-pol` | Dump password policy |
| `--sam` | Dump SAM hashes (requires admin) |
| `--lsa` | Dump LSA secrets (requires admin) |
| `--ntds` | Dump NTDS.dit (DC only, requires admin) |
| `--rid-brute` | RID brute force user enumeration |
| `--bloodhound` | Collect BloodHound data via LDAP |
| `--kerberoasting` | Kerberoast all SPNs |
| `--asreproast` | ASREPRoast all users without pre-auth |
| `-x 'cmd'` | Execute command via cmd.exe |
| `--local-auth` | Authenticate as local account |
| `--continue-on-success` | Keep spraying after valid credential |

---

### Active Directory / Kerberos

| # | Tool | Description |
|---|------|-------------|
| 1 | LDAPSearch | Anonymous LDAP/LDAPS enumeration with auto BaseDN conversion |
| 2 | Responder | LLMNR/NBT-NS/MDNS poisoning for NTLMv2 hash capture |
| 3 | bloodyAD | LDAP-based AD privilege escalation and enumeration |

**bloodyAD** supports password/hash/Kerberos/certificate authentication and the following action categories:

| Action | Examples |
|--------|---------|
| `GET` | `get writable`, `get membership`, `get dnsDump`, `get trusts` |
| `SET` | `set password`, `set owner`, `set rbcd`, `set shadowCredentials`, `set dontreqpreauth` |
| `ADD` | `add groupMember`, `add dcsync`, `add genericAll`, `add rbcd` |
| `REMOVE` | `remove groupMember`, `remove dcsync`, `remove genericAll`, `remove rbcd` |

---

### Brute Force

| # | Tool | Description |
|---|------|-------------|
| 1 | Hydra | Multi-protocol login brute forcer — interactive protocol, port, user, and wordlist selection |

Supported protocols include: `ssh`, `ftp`, `rdp`, `http-get`, `http-post-form`, `smb`, `mssql`, and more.
Default password list: `/usr/share/wordlists/rockyou.txt`

---

### Utilities

| # | Tool | Description |
|---|------|-------------|
| 1 | EyeWitness | Web screenshot and HTML report generation — auto-runs on all configured alt ports |
| 2 | SearchSploit | Local exploit-db keyword search with saved output |

---

## Alternate Port Configuration

RickyRecon supports scanning web interfaces on non-standard ports. Configure alternate ports from:
- **Web Scanning menu** — press `P`
- **Directory Fuzzing menu** — press `P`
- **Main menu** — option `15`

**Port management options:**
- Add one or more ports (space-separated)
- Remove a single port
- Clear all alternate ports

Once configured, every web scanning and directory fuzzing tool automatically runs against the primary target **and** all alternate ports. Output files are named per port to keep results separate.

**Protocol detection:**
- Port 443 / 8443 → HTTPS
- Port 80 → HTTP (no port suffix in URL)
- All other ports → HTTP with explicit port

---

## Output Structure

All output is saved to `recon_reports_<your-machine-hostname>/` in your current working directory. Files inside are named by tool and target IP/hostname.

```
recon_reports_kali/
├── rustscan_10.10.10.1.txt
├── nmap_10.10.10.1.txt
├── nmap_udp_10.10.10.1.txt
├── nmap_snmp_10.10.10.1.txt
├── snmpwalk_public_10.10.10.1.txt
├── snmpwalk_private_10.10.10.1.txt
├── snmpwalk_extend_10.10.10.1.txt
├── snmpwalk_ucd_exec_10.10.10.1.txt
├── snmpv3_valid_users_10.10.10.1.txt
├── snmpset_rce_write_10.10.10.1.txt
├── snmpset_rce_output_10.10.10.1.txt
├── disman_trigger_10.10.10.1.txt
├── snmpcheck_10.10.10.1.txt
├── onesixtyone_10.10.10.1.txt
├── nikto_10.10.10.1.txt
├── gobuster_10.10.10.1.txt
├── ffuf_10.10.10.1.json
├── nuclei_10.10.10.1.txt
├── enum4linux_10.10.10.1.txt
├── nxc_10.10.10.1_smb.txt
├── ldapsearch_10.10.10.1.txt
├── bloodyad_10.10.10.1.txt
├── hydra_10.10.10.1_ssh.txt
├── searchsploit_<term>.txt
└── eyewitness_10.10.10.1/
```

---

## Disclaimer

This tool is intended for authorized penetration testing and security research only. Always obtain explicit written permission before testing any system you do not own. The author assumes no liability for misuse.
