# This is a guide to setting up Nextcloud server with TLS encryption

- Create a domain (example.com) and do port forwarding for ports 80 and 443 if needed (these need to be exposed for nextcloud to work).
- Change domain in `nginx.conf.init_tmp` to proper one.
- Run a temporary docker container to serve the challenge for TLS certificate creation:
	- `docker run -d --name nginx-temp -p 80:80 -v $(pwd)/nginx.conf.init_tmp:/etc/nginx/conf.d/default.conf:ro -v $(pwd)/certbot/www:/var/www/certbot nginx:stable-alpine`
- Initiate TLS certificate creation (change with correct domain):
	- `docker run --rm -it -v $(pwd)/certbot/conf:/etc/letsencrypt -v $(pwd)/certbot/www:/var/www/certbot certbot/certbot certonly --webroot -w /var/www/certbot -d example.com -d nextcloud.example.com`
- Clean up residue container:
	- `docker stop nginx-temp`
	- `docker rm nginx-temp`
- Change the volume mount drive/point and user id (if needed, but needs to be same as in `nextcloud-cron/Dockerfile`), passwords and domains in `docker-compose.yml`
- Create volume mounts for nextcloud if they don't exist using same user id
- Change domains in `nginx.conf` with proper ones.
- Start nextcloud:
	- `docker compose up -d`
- Visit the app at `nextcloud.example.com` and install the app and setup admin user.
- Install Nextcloud android app from playstore and attempt login.
- From web app via browser logged in with admin user go to `Security` under `Personal`, scroll down to `Devices & sessions` and create a new app password
	- This will generate a QR code to be able to login via android app
