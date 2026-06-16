#!/bin/bash

#############################################
# Script pour détecter les équipements actifs
# Affiche la date du dernier log reçu
#############################################

OUTPUT_FILE="/var/www/syslog-viewer/active-devices.json"
CURRENT_LOG_DIR="/mnt/syslog-data/current"

# Date du jour
TODAY=$(date +%Y/%m/%d)
LOG_PATH="$CURRENT_LOG_DIR/$TODAY"

# Fonction pour échapper les caractères spéciaux JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

# Initialiser le fichier JSON avec un tableau vide temporaire
TMP_FILE=$(mktemp)
echo '[' > "$TMP_FILE"

# Vérifier si le répertoire existe et contient des fichiers
if [ -d "$LOG_PATH" ]; then
    # Compter les fichiers .log
    log_file_count=$(find "$LOG_PATH" -name "*.log" -type f 2>/dev/null | wc -l)

    if [ $log_file_count -gt 0 ]; then
        # Parcourir tous les fichiers .log du jour
        first=true
        for logfile in "$LOG_PATH"/*.log; do
            if [ -f "$logfile" ] && [ -s "$logfile" ]; then
                # Extraire le nom de l'équipement
                hostname=$(basename "$logfile" .log)

                # Compter le nombre de lignes (logs) aujourd'hui
                log_count=$(wc -l < "$logfile" 2>/dev/null || echo 0)

                # Ignorer les fichiers vides
                if [ "$log_count" -eq 0 ]; then
                    continue
                fi

                # Dernière ligne de log (échapper les caractères spéciaux)
                last_log=$(tail -n 1 "$logfile" 2>/dev/null || echo "")

                # Extraire le timestamp du dernier log (format ISO si disponible)
                last_timestamp=$(echo "$last_log" | grep -oP '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' || echo "$last_log" | awk '{print $1, $2, $3}' | head -c 50)

                # Si vide, utiliser la date de modification
                if [ -z "$last_timestamp" ]; then
                    last_timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
                fi

                # Date de modification du fichier (timestamp Unix)
                last_modified=$(stat -c %Y "$logfile" 2>/dev/null || echo 0)

                # Convertir en format lisible
                last_seen_date=$(date -d @$last_modified '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Inconnu")

                # Taille du fichier
                file_size=$(du -h "$logfile" 2>/dev/null | awk '{print $1}' || echo "0K")

                # Échapper les valeurs pour JSON
                hostname_safe=$(escape_json "$hostname")
                last_timestamp_safe=$(escape_json "$last_timestamp")
                last_seen_date_safe=$(escape_json "$last_seen_date")

                # Ajouter une virgule sauf pour le premier élément
                if [ "$first" = false ]; then
                    echo ',' >> "$TMP_FILE"
                fi
                first=false

                # Créer l'objet JSON
                cat >> "$TMP_FILE" << EOF
  {
    "hostname": "$hostname_safe",
    "log_count": $log_count,
    "last_log_content": "$last_timestamp_safe",
    "last_modified": "$last_seen_date_safe",
    "file_size": "$file_size"
  }
EOF
            fi
        done
    fi
fi

echo '' >> "$TMP_FILE"
echo ']' >> "$TMP_FILE"

# Déplacer le fichier temporaire vers la destination
mv "$TMP_FILE" "$OUTPUT_FILE"

# Permissions
chmod 644 "$OUTPUT_FILE"
chown www-data:www-data "$OUTPUT_FILE" 2>/dev/null || true

# Log de debug (optionnel)
# echo "[$(date '+%Y-%m-%d %H:%M:%S')] detect-active-devices.sh : $(cat "$OUTPUT_FILE" | wc -l) lignes générées" >> /var/log/detect-active-devices.log
