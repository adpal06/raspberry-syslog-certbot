#!/bin/bash
set -e

echo "========================================"
echo "  Syslog Server - Demarrage Docker"
echo "========================================"

# --- Variables d'environnement ---
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
TIMEZONE="${TIMEZONE:-Europe/Paris}"
RETENTION_DAYS="${RETENTION_DAYS:-365}"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-syslog-docker}"

# --- Fuseau horaire ---
if [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    echo "$TIMEZONE" > /etc/timezone
    echo "[INFO] Fuseau horaire: $TIMEZONE"
fi

# --- Structure des repertoires de donnees ---
echo "[INFO] Creation de la structure de donnees..."
mkdir -p /mnt/syslog-data/current \
         /mnt/syslog-data/archives \
         /mnt/syslog-data/downloads

chown -R syslog:adm /mnt/syslog-data/current
chmod -R 775 /mnt/syslog-data/current
chown -R www-data:www-data /mnt/syslog-data/archives
chmod -R 755 /mnt/syslog-data/archives
chown -R www-data:www-data /mnt/syslog-data/downloads
chmod -R 755 /mnt/syslog-data/downloads

# --- Configuration rsyslog ---
echo "[INFO] Configuration de rsyslog..."
cat > /etc/rsyslog.d/10-remote-syslog.conf << EOF
# Modules pour reception reseau
module(load="imudp")
module(load="imtcp")

# Ecoute UDP sur port 514
input(type="imudp" port="514")

# Ecoute TCP sur port 514
input(type="imtcp" port="514")

# Template pour organiser les fichiers
template(name="DailyPerHost" type="string"
         string="/mnt/syslog-data/current/%\$YEAR%/%\$MONTH%/%\$DAY%/%HOSTNAME%.log")

# Template pour le format des messages
template(name="LogFormat" type="string"
         string="%TIMESTAMP:::date-rfc3339% %HOSTNAME% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n")

# Exclure les logs locaux du serveur (hostname configure, hostname conteneur, localhost)
:hostname, isequal, "$SERVER_HOSTNAME" stop
:hostname, isequal, "$(hostname)" stop
:hostname, isequal, "localhost" stop

# Accepter TOUS les autres logs (distants uniquement)
*.* action(type="omfile" dynaFile="DailyPerHost" template="LogFormat" createDirs="on" dirCreateMode="0775" fileCreateMode="0644")
stop
EOF

# --- Configuration nginx ---
echo "[INFO] Configuration de nginx..."

# Utiliser le htpasswd persistant du volume, ou le creer si absent
HTPASSWD_PERSIST="/mnt/syslog-data/.htpasswd"
if [ -f "$HTPASSWD_PERSIST" ]; then
    echo "[INFO] Fichier htpasswd existant detecte"
else
    echo "[INFO] Creation du fichier htpasswd..."
    htpasswd -bc "$HTPASSWD_PERSIST" admin "$ADMIN_PASSWORD"
fi
cp "$HTPASSWD_PERSIST" /etc/nginx/.htpasswd

cat > /etc/nginx/sites-available/syslog-viewer << 'NGINX_EOF'
server {
    listen 80;
    server_name _;

    root /var/www/syslog-viewer;
    index index.html;

    access_log /var/log/nginx/syslog-viewer-access.log;
    error_log /var/log/nginx/syslog-viewer-error.log;

    client_max_body_size 100M;

    # Authentification pour tout le site
    auth_basic "Serveur Syslog - Authentification requise";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        try_files $uri $uri/ =404;
    }

    location /api/disk-stats {
        default_type application/json;
        alias /var/www/syslog-viewer/disk-stats.json;
    }

    location /disk-history.json {
        default_type application/json;
        alias /var/www/syslog-viewer/disk-history.json;
    }

    location /active-devices.json {
        default_type application/json;
        alias /var/www/syslog-viewer/active-devices.json;
    }

    location /downloads/ {
        alias /mnt/syslog-data/downloads/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        limit_except GET HEAD {
            deny all;
        }

        add_header Content-Disposition "attachment";
        default_type application/gzip;
    }

    location /archives/ {
        alias /mnt/syslog-data/archives/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        limit_except GET HEAD {
            deny all;
        }

        types {
            application/gzip gz;
            text/plain log;
        }
    }

    location /admin {
        alias /var/www/syslog-viewer/admin;
        index admin.html;
    }

    location /admin/archives/ {
        alias /mnt/syslog-data/archives/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_access user:rw group:rw all:r;
        create_full_put_path on;
    }

    location /admin/current/ {
        alias /mnt/syslog-data/current/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    location /admin/downloads/ {
        alias /mnt/syslog-data/downloads/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_access user:rw group:rw all:r;
        create_full_put_path on;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/syslog-viewer /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# --- Protection disque plein ---
MAX_DISK_PERCENT="${MAX_DISK_PERCENT:-90}"
echo "[INFO] Protection disque : arret ecriture si usage > ${MAX_DISK_PERCENT}%"

cat > /usr/local/bin/check-disk-space.sh << 'DISKEOF'
#!/bin/bash
MAX_PERCENT="${MAX_DISK_PERCENT:-90}"
USAGE=$(df /mnt/syslog-data | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$USAGE" -ge "$MAX_PERCENT" ]; then
    if pgrep rsyslogd > /dev/null; then
        logger -t disk-check "Disque a ${USAGE}% (limite: ${MAX_PERCENT}%) - Arret de rsyslog"
        kill $(pgrep rsyslogd) 2>/dev/null || true
    fi
else
    if ! pgrep rsyslogd > /dev/null; then
        logger -t disk-check "Disque a ${USAGE}% - Redemarrage de rsyslog"
        rsyslogd
    fi
fi
DISKEOF
chmod +x /usr/local/bin/check-disk-space.sh

# --- Configuration crontab ---
echo "[INFO] Configuration des taches cron..."
cat > /etc/cron.d/syslog-server << CRON_EOF
# Verification espace disque toutes les 2 minutes
*/2 * * * * root MAX_DISK_PERCENT=${MAX_DISK_PERCENT} /usr/local/bin/check-disk-space.sh
# Initialisation repertoire logs quotidien a minuit
0 0 * * * root /usr/local/bin/init-daily-logs.sh >> /var/log/init-daily-logs.log 2>&1
# Archivage quotidien a 00:30
30 0 * * * root /usr/local/bin/syslog-archiver.sh >> /var/log/syslog-archiver.log 2>&1
# Stats disque toutes les 5 minutes
*/5 * * * * root /usr/local/bin/generate-disk-stats.sh
# Detection equipements toutes les minutes
*/1 * * * * root /usr/local/bin/detect-active-devices.sh
# Generation index telechargements toutes les heures
0 * * * * root /usr/local/bin/generate-downloads-index.sh
CRON_EOF

chmod 0644 /etc/cron.d/syslog-server

# --- Initialisation ---
echo "[INFO] Initialisation des donnees..."

# Creer la structure du jour
/usr/local/bin/init-daily-logs.sh >> /var/log/init-daily-logs.log 2>&1 || true

# Generer les stats initiales
/usr/local/bin/generate-disk-stats.sh 2>/dev/null || true
/usr/local/bin/detect-active-devices.sh 2>/dev/null || true

echo "========================================"
echo "  Syslog Server demarre"
echo "  Interface web : http://localhost/"
echo "  Admin panel   : http://localhost/admin"
echo "  Utilisateur   : admin"
echo "  Syslog ports  : 514 UDP/TCP"
echo "========================================"

# Lancer supervisord (gere rsyslog + nginx + cron)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
