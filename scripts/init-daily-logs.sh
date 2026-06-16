#!/bin/bash

#############################################
# Script d'initialisation des logs quotidiens
# Crée la structure pour le jour actuel
# Novolink Infrastructure
#############################################

LOG_DIR="/mnt/syslog-data/current"
TODAY=$(date +%Y/%m/%d)
YESTERDAY=$(date -d "yesterday" +%Y/%m/%d)
TODAY_DIR="$LOG_DIR/$TODAY"
YESTERDAY_DIR="$LOG_DIR/$YESTERDAY"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] =========================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initialisation des logs du $(date +%d/%m/%Y)"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] =========================================="

# Créer la structure du jour
mkdir -p "$TODAY_DIR"

# Si hier existe, copier la structure (fichiers vides)
if [ -d "$YESTERDAY_DIR" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copie de la structure d'hier..."
    
    for logfile in "$YESTERDAY_DIR"/*.log; do
        if [ -f "$logfile" ]; then
            filename=$(basename "$logfile")
            new_logfile="$TODAY_DIR/$filename"
            
            # Créer un fichier vide
            touch "$new_logfile"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fichier créé: $filename"
        fi
    done
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Création de la structure vide"
fi

# Ajuster les permissions
chown -R syslog:adm "$TODAY_DIR"
chmod 775 "$TODAY_DIR"
find "$TODAY_DIR" -type f -name "*.log" -exec chmod 664 {} \; 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')]  Répertoire créé: $TODAY_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S')]  Permissions: syslog:adm (775)"

# Créer marqueur .ready
touch "$TODAY_DIR/.ready"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Structure créée"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] =========================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initialisation terminée"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] =========================================="
