#!/bin/bash

#############################################
# Script de diagnostic du serveur Syslog
# Vérifie l'installation et identifie les problèmes
# SYIT Infrastructure
#############################################

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
}

print_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   Diagnostic du Serveur Syslog - SYIT         ║"
echo "╚════════════════════════════════════════════════╝"

# ========================================
# 1. Services
# ========================================
print_header "1. Vérification des Services"

if systemctl is-active --quiet rsyslog; then
    print_ok "rsyslog est actif"
else
    print_error "rsyslog n'est PAS actif"
    echo "    → sudo systemctl start rsyslog"
fi

if systemctl is-active --quiet nginx; then
    print_ok "nginx est actif"
else
    print_error "nginx n'est PAS actif"
    echo "    → sudo systemctl start nginx"
fi

# ========================================
# 2. Fichiers d'authentification
# ========================================
print_header "2. Fichiers d'Authentification nginx"

if [ -f /etc/nginx/.htpasswd ]; then
    nb_users=$(wc -l < /etc/nginx/.htpasswd)
    print_ok ".htpasswd existe : $nb_users utilisateur(s)"
    echo "    Utilisateurs :"
    cut -d: -f1 /etc/nginx/.htpasswd | sed 's/^/      - /'

    # Permissions
    perms=$(stat -c %a /etc/nginx/.htpasswd)
    owner=$(stat -c %U:%G /etc/nginx/.htpasswd)
    if [ "$perms" = "644" ] && [ "$owner" = "www-data:www-data" ]; then
        print_ok "Permissions correctes : $perms $owner"
    else
        print_warning "Permissions : $perms $owner (devrait être 644 www-data:www-data)"
        echo "    → sudo chmod 644 /etc/nginx/.htpasswd"
        echo "    → sudo chown www-data:www-data /etc/nginx/.htpasswd"
    fi
else
    print_error ".htpasswd manquant"
    echo "    → Exécutez la configuration nginx à nouveau"
fi

# ========================================
# 3. Structure de répertoires
# ========================================
print_header "3. Structure de Répertoires"

SYSLOG_DATA="/mnt/syslog-data"

if [ -d "$SYSLOG_DATA" ]; then
    print_ok "Point de montage $SYSLOG_DATA existe"

    # Vérifier si monté
    if mountpoint -q "$SYSLOG_DATA"; then
        print_ok "Disque monté sur $SYSLOG_DATA"
        df -h "$SYSLOG_DATA" | tail -1 | awk '{print "    → Espace : " $3 " utilisé / " $2 " total (" $5 ")"}'
    else
        print_error "$SYSLOG_DATA n'est pas un point de montage"
        echo "    → sudo mount -a"
    fi
else
    print_error "$SYSLOG_DATA n'existe pas"
fi

# Vérifier current/
if [ -d "$SYSLOG_DATA/current" ]; then
    perms=$(stat -c "%a %U:%G" "$SYSLOG_DATA/current")
    print_ok "Répertoire current/ existe : $perms"

    # Vérifier la structure du jour
    TODAY=$(date +%Y/%m/%d)
    TODAY_DIR="$SYSLOG_DATA/current/$TODAY"

    if [ -d "$TODAY_DIR" ]; then
        nb_files=$(find "$TODAY_DIR" -name "*.log" 2>/dev/null | wc -l)
        print_ok "Structure du jour existe : $TODAY_DIR"
        print_info "$nb_files fichier(s) .log trouvé(s)"

        if [ $nb_files -gt 0 ]; then
            echo "    Fichiers récents :"
            find "$TODAY_DIR" -name "*.log" -mmin -60 2>/dev/null | head -5 | sed 's/^/      - /' | xargs -I {} basename {}
        fi
    else
        print_warning "Structure du jour manquante : $TODAY_DIR"
        echo "    → sudo /usr/local/bin/init-daily-logs.sh"
    fi
else
    print_error "Répertoire $SYSLOG_DATA/current manquant"
    echo "    → sudo mkdir -p $SYSLOG_DATA/current"
    echo "    → sudo chown -R syslog:adm $SYSLOG_DATA/current"
fi

# ========================================
# 4. Configuration rsyslog
# ========================================
print_header "4. Configuration rsyslog"

if [ -f /etc/rsyslog.d/10-remote-syslog.conf ]; then
    print_ok "Configuration rsyslog existe"

    # Vérifier les ports
    if ss -ulnp | grep -q ":514"; then
        print_ok "Port UDP 514 en écoute"
    else
        print_error "Port UDP 514 non ouvert"
    fi

    if ss -tlnp | grep -q ":514"; then
        print_ok "Port TCP 514 en écoute"
    else
        print_error "Port TCP 514 non ouvert"
    fi
else
    print_error "Configuration rsyslog manquante"
fi

# ========================================
# 5. AppArmor
# ========================================
print_header "5. AppArmor"

if command -v aa-status &> /dev/null; then
    if aa-status 2>/dev/null | grep -q rsyslogd; then
        print_ok "Profil AppArmor rsyslog chargé"

        # Vérifier les denials récents
        denied=$(dmesg | grep -i "apparmor.*denied.*rsyslog" | tail -5)
        if [ -n "$denied" ]; then
            print_warning "Blocages AppArmor détectés récemment :"
            echo "$denied" | sed 's/^/      /'
            echo "    → Vérifiez /etc/apparmor.d/local/usr.sbin.rsyslogd"
        else
            print_ok "Aucun blocage AppArmor récent"
        fi
    else
        print_warning "Profil AppArmor rsyslog non trouvé"
    fi
else
    print_info "AppArmor non disponible"
fi

# ========================================
# 6. Logs rsyslog récents
# ========================================
print_header "6. Logs rsyslog récents"

echo "Dernières lignes de journalctl pour rsyslog :"
journalctl -u rsyslog -n 10 --no-pager 2>/dev/null | sed 's/^/  /'

# ========================================
# 7. Test de connexion
# ========================================
print_header "7. Test de Réception de Logs"

print_info "Envoi d'un message de test..."
logger -n 127.0.0.1 -P 514 "TEST DIAGNOSTIC $(date '+%Y-%m-%d %H:%M:%S')"
sleep 2

# Chercher le message
TODAY=$(date +%Y/%m/%d)
HOSTNAME=$(hostname)
TEST_FILE="$SYSLOG_DATA/current/$TODAY/$HOSTNAME.log"

if [ -f "$TEST_FILE" ]; then
    if grep -q "TEST DIAGNOSTIC" "$TEST_FILE" 2>/dev/null; then
        print_ok "Message de test reçu et enregistré"
    else
        print_warning "Fichier existe mais message de test non trouvé"
        echo "    → Dernières lignes du fichier :"
        tail -3 "$TEST_FILE" 2>/dev/null | sed 's/^/      /'
    fi
else
    print_error "Fichier de log non créé : $TEST_FILE"
    echo "    → Vérifiez la configuration rsyslog"
    echo "    → Vérifiez les permissions"
    echo "    → Vérifiez AppArmor"
fi

# ========================================
# 8. Résumé
# ========================================
print_header "8. Résumé et Recommandations"

IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo ""
echo "🌐 Interface web : http://$IP_ADDRESS/"
echo "🔧 Panel admin   : http://$IP_ADDRESS/admin"
echo ""
echo "Commandes utiles :"
echo "  • Redémarrer rsyslog : sudo systemctl restart rsyslog"
echo "  • Vérifier les logs  : sudo journalctl -u rsyslog -f"
echo "  • Créer structure    : sudo /usr/local/bin/init-daily-logs.sh"
echo "  • Vérifier AppArmor  : sudo dmesg | grep -i denied"
echo ""
