FROM nginxinc/nginx-unprivileged:stable-alpine-slim

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080