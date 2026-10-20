FROM php:8.4-fpm-bookworm

ENV APACHE_CONFDIR=/etc/apache2 \
    APACHE_ENVVARS=/etc/apache2/envvars \
    DEBIAN_FRONTEND=noninteractive \
    DRUSH_VERSION=8.4.10 \
    DRUSH_LAUNCHER_VERSION=0.10.1 \
    DRUSH_LAUNCHER_FALLBACK=/usr/local/drush/drush

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apache2 \
        ca-certificates \
        default-mysql-client \
        exim4 \
        git \
        imagemagick \
        libavif-dev \
        libbz2-dev \
        libfreetype6-dev \
        libgpgme-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libmagickwand-dev \
        libmemcached-dev \
        libpng-dev \
        libpq-dev \
        libsasl2-dev \
        libwebp-dev \
        libxml2-dev \
        libzip-dev \
        nano \
        rsyslog \
        unzip \
        zip \
        zlib1g-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp --with-avif; \
    # ftp_ssl_connect() only exists when HAVE_FTP_SSL is set. ext/ftp enables
    # it implicitly from --with-openssl at the PHP configure step, which does
    # not happen for a shared phpize build, so ask for it explicitly. Without
    # this the extension loads but lags php8.3, which has openssl linked in.
    docker-php-ext-configure ftp --with-ftp-ssl; \
    docker-php-ext-install -j"$(nproc)" \
        bz2 \
        ftp \
        gd \
        intl \
        opcache \
        pdo_mysql \
        pdo_pgsql \
        soap \
        sockets \
        zip; \
    yes '' | pecl install apcu gnupg memcached imagick; \
    pecl clear-cache; \
    docker-php-ext-enable apcu gnupg memcached imagick; \
    a2dismod mpm_event || true; \
    a2enmod mpm_prefork proxy proxy_fcgi proxy_http rewrite; \
    sed -ri 's!^([[:space:]]*)DocumentRoot .+!\1DocumentRoot /var/www/html/docroot!' /etc/apache2/sites-available/000-default.conf; \
    sed -i '/^ServerTokens/d; /^ServerSignature/d' /etc/apache2/apache2.conf; \
    printf 'ServerTokens Prod\nServerSignature Off\n' >> /etc/apache2/apache2.conf; \
    sed -ri 's!^user = .+!user = docker!; s!^group = .+!group = docker!' /usr/local/etc/php-fpm.d/www.conf; \
    groupadd -g 1001 docker; \
    useradd -u 1000 -g docker -m -s /bin/sh docker; \
    # php-fpm serves as `docker` and gpg needs a writable keyring directory;
    # without one gnupg::encrypt() silently returns an empty string. php8.3
    # provisions /var/www/.gnupg for the same reason -- 8.4's fpm runs as
    # `docker`, so the keyring lives in that user's home instead.
    install -d -m 700 -o docker -g docker /home/docker/.gnupg; \
    ln -sf /usr/bin/mysqldump /usr/bin/mariadb-dump || true; \
    # The base image ships /var/www/html owned by www-data; php8.3 chowns it
    # to the app user, so match that here.
    mkdir -p /var/www/html; \
    chown docker:docker /var/www/html; \
    chmod 777 /var/www/html; \
    rm -rf /var/lib/apt/lists/*

# Install new relic agent
# Pinned releases are only served from the per-version archive path; the
# /release/ directory now contains just the newest agent, so it 404s.
# 12.6.0.34 ships newrelic-20240924.so, which matches the PHP 8.4 module API.
RUN set -eux; \
    cd /tmp; \
    curl -fsSL -o newrelic.tar.gz https://download.newrelic.com/php_agent/archive/12.6.0.34/newrelic-php5-12.6.0.34-linux.tar.gz; \
    gzip -dc newrelic.tar.gz | tar xf -; \
    cd newrelic-php5-12.6.0.34-linux; \
    NR_INSTALL_USE_CP_NOT_LN=1 NR_INSTALL_SILENT=1 ./newrelic-install install; \
    rm -rf /tmp/newrelic-php5-12.6.0.34-linux /tmp/newrelic.tar.gz; \
    sed -i \
        -e 's/;newrelic.enabled =.*/newrelic.enabled = false/' \
        -e 's/;newrelic.daemon.dont_launch =.*/newrelic.daemon.dont_launch = 3/' \
        /usr/local/etc/php/conf.d/newrelic.ini

# Land on the same path the compose file bind-mounts, so the mount replaces this
# file instead of sitting beside it (same as php8.2/8.3). Any name sorting after
# "php.ini" wins the conf.d scan order and silently overrides the mounted config.
COPY php.ini /usr/local/etc/php/conf.d/php.ini
COPY config/rsyslog.conf /etc/rsyslog.conf
COPY docker-php.conf /etc/apache2/conf-enabled/docker-php.conf
COPY apache2-foreground /usr/local/bin/apache2-foreground
COPY start.sh /start.sh

RUN chmod +x /usr/local/bin/apache2-foreground /start.sh

# Drush CLI, matching php8.1/8.2/8.3-fpm-apache. /usr/local/bin/drush is the
# launcher: it prefers a site-local vendor/bin/drush and only falls back to
# the phar below. DRUSH_LAUNCHER_FALLBACK has to point at that phar, otherwise
# the launcher exits non-zero outside a Drupal site (which also fails the build).
RUN set -eux; \
    mkdir -p /usr/local/drush; \
    curl -fsSL -o /usr/local/drush/drush "https://github.com/drush-ops/drush/releases/download/${DRUSH_VERSION}/drush.phar"; \
    curl -fsSL -o /usr/local/bin/drush "https://github.com/drush-ops/drush-launcher/releases/download/${DRUSH_LAUNCHER_VERSION}/drush.phar"; \
    chmod +x /usr/local/drush/drush /usr/local/bin/drush; \
    drush --version

# Apache's logs have to reach `docker logs`. Debian's apache2 writes them to
# regular files under /var/log/apache2, so error/access logs stay invisible to
# `docker logs` -- which is how the production crash loop was diagnosed.
# Symlink them to stdout/stderr, as php8.2/php8.3-fpm-apache already do.
RUN set -eux; \
    ln -sfT /dev/stderr /var/log/apache2/error.log; \
    ln -sfT /dev/stdout /var/log/apache2/access.log; \
    ln -sfT /dev/stdout /var/log/apache2/other_vhosts_access.log

WORKDIR /var/www/html
EXPOSE 80
CMD ["/start.sh"]
