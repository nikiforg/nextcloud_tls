# nextcloud-cron/Dockerfile
FROM nextcloud:latest

USER root

RUN apt-get update && apt-get install -y cron && rm -rf /var/lib/apt/lists/*

RUN id -u 1000 >/dev/null 2>&1 || useradd -u 1000 -m nextcloud

# Install crontab for the user
RUN echo '*/5 * * * * /usr/local/bin/php -d memory_limit=1024M -f /var/www/html/cron.php >> /tmp/cron.log 2>&1' | crontab -u nextcloud -

CMD ["cron", "-f"]
