FROM nginxinc/nginx-unprivileged:stable-alpine

COPY index.html /usr/share/nginx/html/index.html


# unpriviledged runs on 8080
EXPOSE 8080