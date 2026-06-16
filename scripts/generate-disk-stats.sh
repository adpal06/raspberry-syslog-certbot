#!/bin/bash

OUTPUT_FILE="/var/www/syslog-viewer/disk-stats.json"
HISTORY_FILE="/var/www/syslog-viewer/disk-history.json"
MOUNT_POINT="/mnt/syslog-data"
MAX_HISTORY=168

# Récupérer les infos disque
DISK_INFO=$(df -BG "$MOUNT_POINT" | tail -1)
TOTAL=$(echo $DISK_INFO | awk '{print $2}' | sed 's/G//')
USED=$(echo $DISK_INFO | awk '{print $3}' | sed 's/G//')
FREE=$(echo $DISK_INFO | awk '{print $4}' | sed 's/G//')
PERCENT=$(echo $DISK_INFO | awk '{print $5}' | sed 's/%//')

TIMESTAMP=$(date -Iseconds)
TIMESTAMP_DISPLAY=$(date '+%Y-%m-%d %H:%M')

# Générer le JSON des stats actuelles
cat > "$OUTPUT_FILE" << EOF
{
    "total_gb": "$TOTAL",
    "used_gb": "$USED",
    "free_gb": "$FREE",
    "usage_percent": "$PERCENT",
    "timestamp": "$TIMESTAMP",
    "timestamp_display": "$TIMESTAMP_DISPLAY"
}
EOF

chmod 644 "$OUTPUT_FILE"

# Gestion de l'historique
if [ ! -f "$HISTORY_FILE" ]; then
    echo '{"history":[]}' > "$HISTORY_FILE"
fi

HISTORY=$(cat "$HISTORY_FILE")

NEW_ENTRY=$(cat << EOF
{
    "timestamp": "$TIMESTAMP",
    "timestamp_display": "$TIMESTAMP_DISPLAY",
    "used_gb": $USED,
    "free_gb": $FREE,
    "usage_percent": $PERCENT
}
EOF
)

# Ajouter la nouvelle entrée et limiter l'historique
python3 << PYTHON
import json
import sys

try:
    with open("$HISTORY_FILE", "r") as f:
        data = json.load(f)
    
    new_entry = $NEW_ENTRY
    data["history"].append(new_entry)
    
    if len(data["history"]) > $MAX_HISTORY:
        data["history"] = data["history"][-$MAX_HISTORY:]
    
    with open("$HISTORY_FILE", "w") as f:
        json.dump(data, f, indent=2)
    
except Exception as e:
    print(f"Erreur: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON

chmod 644 "$HISTORY_FILE"
