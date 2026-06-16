#!/bin/bash

# Script d'archivage quotidien des logs avec création d'archives .tar.gz téléchargeables

CURRENT_DIR="/mnt/syslog-data/current"
ARCHIVE_DIR="/mnt/syslog-data/archives"
DOWNLOAD_DIR="/mnt/syslog-data/downloads"
RETENTION_DAYS=365
LOG_FILE="/var/log/syslog-archiver.log"

# Fonction de log
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Date d'hier
YESTERDAY=$(date -d "yesterday" +%Y/%m/%d)
YEAR=$(date -d "yesterday" +%Y)
MONTH=$(date -d "yesterday" +%m)
DAY=$(date -d "yesterday" +%d)
DATE_STRING=$(date -d "yesterday" +%Y-%m-%d)

# Créer les structures si nécessaires
mkdir -p "$ARCHIVE_DIR/$YEAR/$MONTH/$DAY"
mkdir -p "$DOWNLOAD_DIR/$YEAR/$MONTH"

log_message "========== Début de l'archivage pour le $DATE_STRING =========="

# Vérifier si les logs d'hier existent
if [ -d "$CURRENT_DIR/$YESTERDAY" ]; then
    log_message "Logs trouvés pour le $YESTERDAY"
    
    FILE_COUNT=$(find "$CURRENT_DIR/$YESTERDAY" -type f -name "*.log" | wc -l)
    log_message "Nombre de fichiers à archiver: $FILE_COUNT"
    
    if [ $FILE_COUNT -eq 0 ]; then
        log_message "ATTENTION: Aucun fichier .log trouvé pour cette journée"
    else
        # 1. Copier les logs bruts dans archives
        log_message "Copie des logs vers $ARCHIVE_DIR/$YEAR/$MONTH/$DAY/"
        cp -r "$CURRENT_DIR/$YESTERDAY"/* "$ARCHIVE_DIR/$YEAR/$MONTH/$DAY/" 2>&1 | tee -a "$LOG_FILE"
        
        # 2. Compresser individuellement chaque fichier
        log_message "Compression des fichiers individuels..."
        find "$ARCHIVE_DIR/$YEAR/$MONTH/$DAY/" -type f -name "*.log" -exec gzip -9 {} \; 2>&1 | tee -a "$LOG_FILE"
        
        # 3. Créer une archive .tar.gz de toute la journée
        ARCHIVE_NAME="logs-$DATE_STRING.tar.gz"
        ARCHIVE_PATH="$DOWNLOAD_DIR/$YEAR/$MONTH/$ARCHIVE_NAME"
        
        log_message "Création de l'archive téléchargeable: $ARCHIVE_NAME"
        tar -czf "$ARCHIVE_PATH" -C "$CURRENT_DIR/$YEAR/$MONTH" "$DAY" 2>&1 | tee -a "$LOG_FILE"
        
        if [ -f "$ARCHIVE_PATH" ]; then
            ARCHIVE_SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)
            log_message "Archive créée avec succès: $ARCHIVE_PATH ($ARCHIVE_SIZE)"
            chmod 644 "$ARCHIVE_PATH"
        else
            log_message "ERREUR: Échec de la création de l'archive"
        fi
        
        # 4. Supprimer les fichiers sources
        log_message "Nettoyage des fichiers sources dans current/"
        rm -rf "$CURRENT_DIR/$YESTERDAY"
        
        log_message "Archivage terminé avec succès"
    fi
else
    log_message "ATTENTION: Aucun répertoire trouvé pour $YESTERDAY"
fi

# Nettoyage des archives > 365 jours
log_message "Nettoyage des archives de plus de $RETENTION_DAYS jours"

DELETED_FILES=$(find "$ARCHIVE_DIR" -type f -mtime +$RETENTION_DAYS -delete -print | wc -l)
log_message "Fichiers individuels supprimés: $DELETED_FILES"

DELETED_ARCHIVES=$(find "$DOWNLOAD_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
log_message "Archives .tar.gz supprimées: $DELETED_ARCHIVES"

find "$ARCHIVE_DIR" -type d -empty -delete
find "$DOWNLOAD_DIR" -type d -empty -delete

# Statistiques disque
DISK_USAGE=$(df -h /mnt/syslog-data | tail -1 | awk '{print $5}')
DISK_USED=$(df -h /mnt/syslog-data | tail -1 | awk '{print $3}')
DISK_TOTAL=$(df -h /mnt/syslog-data | tail -1 | awk '{print $2}')
log_message "Utilisation disque: $DISK_USAGE ($DISK_USED / $DISK_TOTAL)"

# Générer un index HTML des téléchargements
log_message "Génération de l'index des téléchargements"
/usr/local/bin/generate-downloads-index.sh

log_message "========== Fin de l'archivage =========="
echo "" >> "$LOG_FILE"

exit 0 
