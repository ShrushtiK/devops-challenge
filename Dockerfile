FROM nginxinc/nginx-unprivileged:stable-alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80