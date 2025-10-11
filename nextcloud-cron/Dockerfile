# nextcloud-cron/Dockerfile
FROM nextcloud:latest

USER root

# install cron and cleanup apt lists
RUN apt-get update && apt-get install -y cron && rm -rf /var/lib/apt/lists/*

# create a user with UID 1000 if it doesn't already exist (name: nextcloud)
RUN id -u 1000 >/dev/null 2>&1 || useradd -u 1000 -m nextcloud

# create cron job that runs as 'nextcloud' (UID 1000) every 5 minutes
RUN printf "*/5 * * * * nextcloud php -f /var/www/html/cron.php\n" > /etc/cron.d/nextcloud_cron && \
    chmod 644 /etc/cron.d/nextcloud_cron

# ensure cron picks up the file (cron reads /etc/cron.d/)
CMD ["cron", "-f"]
