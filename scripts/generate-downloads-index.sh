#!/bin/bash
# Script de génération de l'index des téléchargements

OUTPUT_FILE="/var/www/syslog-viewer/downloads-index-auto.json"
DOWNLOAD_DIR="/mnt/syslog-data/downloads"

# Créer un JSON avec la liste des archives
echo '{' > "$OUTPUT_FILE"
echo '  "generated": "'$(date -Iseconds)'",' >> "$OUTPUT_FILE"
echo '  "archives": [' >> "$OUTPUT_FILE"

first=true
find "$DOWNLOAD_DIR" -name "*.tar.gz" -type f | sort -r | while read filepath; do
    filename=$(basename "$filepath")
    filesize=$(du -h "$filepath" | awk '{print $1}')
    filedate=$(stat -c %y "$filepath" | cut -d' ' -f1)
    
    if [ "$first" = false ]; then
        echo ',' >> "$OUTPUT_FILE"
    fi
    first=false
    
    cat >> "$OUTPUT_FILE" << EOF
    {
      "filename": "$filename",
      "size": "$filesize",
      "date": "$filedate",
      "path": "$filepath"
    }
EOF
done

echo '' >> "$OUTPUT_FILE"
echo '  ]' >> "$OUTPUT_FILE"
echo '}' >> "$OUTPUT_FILE"

chmod 644 "$OUTPUT_FILE"
