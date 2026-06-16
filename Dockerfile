FROM ubuntu:22.04

LABEL maintainer="Novolink"
LABEL description="Serveur Syslog centralise avec interface web"

# Eviter les prompts interactifs
ENV DEBIAN_FRONTEND=noninteractive

# Installation des paquets
RUN apt-get update && apt-get install -y --no-install-recommends \
    rsyslog \
    nginx \
    apache2-utils \
    python3 \
    cron \
    supervisor \
    procps \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Structure des repertoires
RUN mkdir -p /mnt/syslog-data/current \
             /mnt/syslog-data/archives \
             /mnt/syslog-data/downloads \
             /var/www/syslog-viewer/admin \
             /var/log/supervisor

# Copier les fichiers web
COPY web/index.html /var/www/syslog-viewer/index.html
COPY web/downloads-index.html /var/www/syslog-viewer/downloads-index.html
COPY web/admin/admin.html /var/www/syslog-viewer/admin/admin.html

# Copier les scripts
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Copier les fichiers de configuration Docker
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Permissions web
RUN chown -R www-data:www-data /var/www/syslog-viewer && \
    chmod -R 755 /var/www/syslog-viewer

# Supprimer la config nginx par defaut
RUN rm -f /etc/nginx/sites-enabled/default

# Ports : 514 UDP/TCP (syslog) + 80 (web)
EXPOSE 514/udp 514/tcp 80

# Volume pour les donnees persistantes
VOLUME ["/mnt/syslog-data"]

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD pgrep rsyslogd > /dev/null && pgrep nginx > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
