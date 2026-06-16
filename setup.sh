#!/bin/bash

#############################################
# Script de lancement Docker
# Serveur Syslog centralise - SYIT
#############################################

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error()   { echo -e "${RED}[X]${NC} $1"; }

clear
echo ""
echo "========================================================"
echo "   Serveur Syslog Centralise - Configuration Docker"
echo "   SYIT Infrastructure"
echo "========================================================"
echo ""

# --- Mot de passe ---
echo ""
print_info "Configuration de l'acces web"
echo ""
while true; do
    read -s -p "  Mot de passe pour l'utilisateur ADMIN : " ADMIN_PASSWORD
    echo ""
    read -s -p "  Confirmer le mot de passe : " ADMIN_PASSWORD_CONFIRM
    echo ""
    if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
        if [ -z "$ADMIN_PASSWORD" ]; then
            print_warning "Le mot de passe ne peut pas etre vide"
        else
            break
        fi
    else
        print_warning "Les mots de passe ne correspondent pas, reessayez"
    fi
done
print_success "Mot de passe configure"

# --- Chemin de stockage ---
echo ""
print_info "Configuration du stockage des logs"
echo ""
echo "  Disques disponibles :"
echo ""
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null | grep -v "loop" || true
echo ""
echo "  Indiquez le chemin du dossier de stockage des logs."
echo "  Exemples : /mnt/usb, /media/ssd, /srv/syslog-data, ./data"
echo ""
read -p "  Chemin de stockage [./data] : " SYSLOG_DATA_PATH
SYSLOG_DATA_PATH="${SYSLOG_DATA_PATH:-./data}"

# Creer le dossier si necessaire et convertir en chemin absolu (requis pour Docker)
mkdir -p "$SYSLOG_DATA_PATH"
SYSLOG_DATA_PATH="$(cd "$SYSLOG_DATA_PATH" && pwd)"
print_success "Stockage : $SYSLOG_DATA_PATH"

# --- Fuseau horaire ---
echo ""
CURRENT_TZ=$(cat /etc/timezone 2>/dev/null || echo "Europe/Paris")
read -p "  Fuseau horaire [$CURRENT_TZ] : " TIMEZONE
TIMEZONE="${TIMEZONE:-$CURRENT_TZ}"
print_success "Fuseau horaire : $TIMEZONE"

# --- Resume ---
echo ""
echo "========================================================"
echo "   Resume de la configuration"
echo "========================================================"
echo ""
echo "  Utilisateur web  : admin"
echo "  Stockage logs    : $SYSLOG_DATA_PATH"
echo "  Fuseau horaire   : $TIMEZONE"
echo "  Port syslog      : 514 (UDP/TCP)"
echo "  Port web         : 80"
echo ""
echo "========================================================"
echo ""
read -p "  Lancer le serveur avec cette configuration ? (o/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Oo]$ ]]; then
    print_warning "Lancement annule"
    exit 0
fi
 
# --- Creation du fichier htpasswd dans le dossier de donnees ---
print_info "Creation du fichier htpasswd..."
mkdir -p "$SYSLOG_DATA_PATH"
if command -v htpasswd > /dev/null 2>&1; then
    htpasswd -bc "$SYSLOG_DATA_PATH/.htpasswd" admin "$ADMIN_PASSWORD"
else
    # htpasswd pas installe sur l'hote, on le cree via docker (httpd:alpine inclut htpasswd)
    docker run --rm -v "$SYSLOG_DATA_PATH:/data" httpd:alpine \
        htpasswd -bc /data/.htpasswd admin "$ADMIN_PASSWORD"
fi
chmod 644 "$SYSLOG_DATA_PATH/.htpasswd"
print_success "Mot de passe sauvegarde dans $SYSLOG_DATA_PATH/.htpasswd"
echo ""

# --- Lancement Docker ---
echo ""
print_info "Construction et lancement du conteneur..."
echo ""

docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d --build

echo ""
echo "========================================================"
echo ""
print_success "Serveur Syslog demarre !"
echo ""
echo "  Interface web : http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')/index.html"
echo "  Panel admin   : http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')/admin"
echo "  Utilisateur   : admin"
echo "  Syslog ports  : 514 UDP/TCP"
echo ""
echo "  Commandes utiles :"
echo "    docker compose logs -f     # Voir les logs"
echo "    docker compose down        # Arreter"
echo "    docker compose restart     # Redemarrer"
echo ""
echo "========================================================"
