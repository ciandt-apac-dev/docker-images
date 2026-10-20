#!/bin/bash
set -e

if [ "$(id -u docker)" != "${CURRENT_USER_UID:-1000}" ]; then
    usermod -u "${CURRENT_USER_UID:-1000}" docker
fi

if [ "$(id -g docker)" != "${CURRENT_USER_GID:-1001}" ]; then
    groupmod -g "${CURRENT_USER_GID:-1001}" docker
fi

# The base image ships /var/www/html owned by www-data; php-fpm serves requests
# as `docker`, so hand the docroot to it. Matches php8.3-fpm-apache. Note this
# recurses into a bind-mounted docroot, so it also rewrites host-side ownership.
chown -R docker:docker /var/www/html

if [ ! -e /usr/bin/mariadb-dump ]; then
    ln -s /usr/bin/mysqldump /usr/bin/mariadb-dump
fi
# No stdout/stderr redirect here, matching php8.1/8.2/8.3. rsyslog.conf routes
# everything to /dev/stdout, which the container's syslog logging driver forwards
# to tdk-syslog; redirecting to a file instead silently cuts the container off
# from tdk-syslog.
nohup rsyslogd -n -f /etc/rsyslog.conf &
update-ca-certificates
service exim4 start || true
php-fpm -D
exec apache2-foreground
