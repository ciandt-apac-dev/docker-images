FROM debian:bookworm-slim

# prevent Debian's PHP packages from being installed
# https://github.com/docker-library/php/pull/542
RUN set -eux; \
	{ \
		echo 'Package: php*'; \
		echo 'Pin: release *'; \
		echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php

# dependencies required for running "phpize"
# (see persistent deps below)
ENV PHPIZE_DEPS \
		autoconf \
		dpkg-dev \
		file \
		g++ \
		gcc \
		libc-dev \
		make \
		pkg-config \
		re2c

ENV DEBIAN_FRONTEND=noninteractive \
	APACHE_CONFDIR=/etc/apache2 \
	APACHE_ENVVARS=/etc/apache2/envvars \
	DRUSH_VERSION=8.4.10 \
	DRUSH_LAUNCHER_VERSION=0.10.1 \
	DRUSH_LAUNCHER_FALLBACK=/usr/local/drush/drush

# persistent / runtime deps
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		$PHPIZE_DEPS \
		ca-certificates \
		curl \
		xz-utils \
		exim4

# php-fpm serves as `docker` and gpg needs a writable keyring directory;
# without one gnupg::encrypt() silently returns an empty string.
RUN groupadd -g 1001 docker \
	&& useradd -u 1000 -g docker -m -s /bin/sh docker \
	&& install -d -m 700 -o docker -g docker /home/docker/.gnupg

ENV PHP_INI_DIR=/usr/local/etc/php
RUN set -eux; \
	mkdir -p "$PHP_INI_DIR/conf.d"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
	[ ! -d /var/www/html ]; \
	mkdir -p /var/www/html; \
	chown docker:docker /var/www/html; \
	chmod 777 /var/www/html

# Install apache2
RUN set -eux; \
	apt-get install -y --no-install-recommends apache2; \
	\
# generically convert lines like
#   export APACHE_RUN_USER=www-data
# into
#   : ${APACHE_RUN_USER:=www-data}
#   export APACHE_RUN_USER
# so that they can be overridden at runtime ("-e APACHE_RUN_USER=...")
	sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS"; \
	\
# setup directories and permissions
	. "$APACHE_ENVVARS"; \
	for dir in \
		"$APACHE_LOCK_DIR" \
		"$APACHE_RUN_DIR" \
		"$APACHE_LOG_DIR" \
	; do \
		rm -rvf "$dir"; \
		mkdir -p "$dir"; \
		chown "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
		chmod 777 "$dir"; \
	done; \
	\
# delete the "index.html" that installing Apache drops in here
	rm -rvf /var/www/html/*; \
	\
# logs should go to stdout / stderr
	ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"; \
	chown -R --no-dereference "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$APACHE_LOG_DIR"

# Use preforking Apache. mpm_event/worker create a pthread per worker, and
# hardened container runtimes (seccomp) deny thread creation with EPERM --
# httpd then exits at startup and the container crash-loops. prefork is
# process-based and needs no threads.
RUN a2dismod mpm_event || true; \
	a2enmod mpm_prefork proxy proxy_fcgi proxy_http rewrite; \
	sed -ri 's!^([[:space:]]*)DocumentRoot .+!\1DocumentRoot /var/www/html/docroot!' /etc/apache2/sites-available/000-default.conf; \
	sed -i '/^ServerTokens/d; /^ServerSignature/d' /etc/apache2/apache2.conf; \
	printf 'ServerTokens Prod\nServerSignature Off\n' >> /etc/apache2/apache2.conf

COPY docker-php.conf /etc/apache2/conf-enabled/docker-php.conf

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# https://github.com/docker-library/php/issues/272
# -D_LARGEFILE_SOURCE and -D_FILE_OFFSET_BITS=64 (https://www.php.net/manual/en/intro.filesystem.php)
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

# 8.4 release keys. 9D7F99A0 (Calvin Buckley) signs 8.4.27 and is not published
# on keys.openpgp.org; fetch the armored keys over HTTPS instead.
ENV GPG_KEYS="AFD8691FDAEDF03BDF6E460563F15A9B715376CA 9D7F99A0CB8F05C8A6958D6256A97AF7600A39A6 0616E93D95AF471243E26761770426E17EBBB3DD"

ENV PHP_VERSION=8.4.27
ENV PHP_URL="https://www.php.net/distributions/php-8.4.27.tar.xz" PHP_ASC_URL="https://www.php.net/distributions/php-8.4.27.tar.xz.asc"
ENV PHP_SHA256="dcf93923b0e38e0d5252b25b796520b5a47761a08b3488b6d0b5d1115764d3f0"

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends gnupg dirmngr; \
	rm -rf /var/lib/apt/lists/*; \
	\
	mkdir -p /usr/src; \
	cd /usr/src; \
	\
	curl -fsSL -o php.tar.xz "$PHP_URL"; \
	\
	if [ -n "$PHP_SHA256" ]; then \
		echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
	fi; \
	\
	if [ -n "$PHP_ASC_URL" ]; then \
		curl -fsSL -o php.tar.xz.asc "$PHP_ASC_URL"; \
		export GNUPGHOME="$(mktemp -d)"; \
		for key in $GPG_KEYS; do \
			curl -fsSL -o "${key}.asc" "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${key}"; \
			gpg --batch --import "${key}.asc"; \
		done; \
		gpg --batch --verify php.tar.xz.asc php.tar.xz; \
		gpgconf --kill all; \
		rm -rf "$GNUPGHOME"; \
	fi; \
	\
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false

COPY docker-php-source /usr/local/bin/

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libargon2-dev \
		libcurl4-openssl-dev \
		libonig-dev \
		libreadline-dev \
		libsodium-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		zlib1g-dev \
	; \
	\
	export \
		CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS" \
	; \
	docker-php-source extract; \
	cd /usr/src/php; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
# https://bugs.php.net/bug.php?id=74125
	if [ ! -d /usr/include/curl ]; then \
		ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; \
	fi; \
	./configure \
		--build="$gnuArch" \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		\
# make sure invalid --configure-flags are fatal errors instead of just warnings
		--enable-option-checking=fatal \
		\
# https://github.com/docker-library/php/issues/439
		--with-mhash \
		\
# https://github.com/docker-library/php/issues/822
		--with-pic \
		\
# --enable-ftp is included here because ftp_ssl_connect() needs ftp to be compiled statically (see https://github.com/docker-library/php/issues/236)
		--enable-ftp \
# --enable-mbstring is included here because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
		--enable-mbstring \
# --enable-mysqlnd is included here because it's harder to compile after the fact than extensions are (since it's a plugin for several extensions, not an extension in itself)
		--enable-mysqlnd \
# https://wiki.php.net/rfc/argon2_password_hash
		--with-password-argon2 \
# https://wiki.php.net/rfc/libsodium
		--with-sodium=shared \
# always build against system sqlite3 (https://github.com/php/php-src/commit/6083a387a81dbbd66d6316a3a12a63f06d5f7109)
		--with-pdo-sqlite=/usr \
		--with-sqlite3=/usr \
		\
		--with-curl \
		--with-iconv \
		--with-openssl \
		--with-readline \
		--with-zlib \
		\
# https://github.com/bwoebi/phpdbg-docs/issues/1#issuecomment-163872806 ("phpdbg is primarily a CLI debugger, and is not suitable for debugging an fpm stack.")
		--disable-phpdbg \
		\
# in PHP 7.4+, the pecl/pear installers are officially deprecated (requiring an explicit "--with-pear")
		--with-pear \
		\
# bundled pcre does not support JIT on s390x
# https://manpages.debian.org/bullseye/libpcre3-dev/pcrejit.3.en.html#AVAILABILITY_OF_JIT_SUPPORT
		$(test "$gnuArch" = 's390x-linux-gnu' && echo '--without-pcre-jit') \
		--with-libdir="lib/$debMultiarch" \
		\
		--disable-cgi \
		\
		--enable-fpm \
		--with-fpm-user=docker \
		--with-fpm-group=docker \
	; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find \
		/usr/local \
		-type f \
		-perm '/0111' \
		-exec sh -euxc ' \
			strip --strip-all "$@" || : \
		' -- '{}' + \
	; \
	make clean; \
	\
# https://github.com/docker-library/php/issues/692 (copy default example "php.ini" files somewhere easily discoverable)
	cp -v php.ini-* "$PHP_INI_DIR/"; \
	\
	cd /; \
	docker-php-source delete; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u \
		| xargs -rt dpkg-query --search \
		| awk 'sub(":$", "", $1) { print $1 }' \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
# update pecl channel definitions https://github.com/docker-library/php/issues/443
	pecl update-channels; \
	rm -rf /tmp/pear ~/.pearrc; \
	\
# smoke test
	php --version

COPY docker-php-ext-* docker-php-entrypoint /usr/local/bin/

# sodium was built as a shared module (so that it can be replaced later if so desired), so let's enable it too (https://github.com/docker-library/php/issues/598)
RUN docker-php-ext-enable sodium

# temporary "freetype-config" workaround for https://github.com/docker-library/php/issues/865 (https://bugs.php.net/bug.php?id=76324)
RUN { echo '#!/bin/sh'; echo 'exec pkg-config "$@" freetype2'; } > /usr/local/bin/freetype-config && chmod +x /usr/local/bin/freetype-config

ENTRYPOINT ["docker-php-entrypoint"]
# https://httpd.apache.org/docs/2.4/stopping.html#gracefulstop
STOPSIGNAL SIGWINCH

COPY apache2-foreground /usr/local/bin/
WORKDIR /var/www/html

RUN set -eux; \
	cd /usr/local/etc; \
	if [ -d php-fpm.d ]; then \
		# for some reason, upstream's php-fpm.conf.default has "include=NONE/etc/php-fpm.d/*.conf"
		sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
		cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
	else \
		# PHP 5.x doesn't use "include=" by default, so we'll create our own simple config that mimics PHP 7+ for consistency
		mkdir php-fpm.d; \
		cp php-fpm.conf.default php-fpm.d/www.conf; \
		{ \
			echo '[global]'; \
			echo 'include=etc/php-fpm.d/*.conf'; \
		} | tee php-fpm.conf; \
	fi; \
	{ \
		echo '[global]'; \
		echo 'error_log = /proc/self/fd/2'; \
		echo; echo '; https://github.com/docker-library/php/pull/725#issuecomment-443540114'; echo 'log_limit = 8192'; \
		echo; \
		echo '[www]'; \
		echo '; if we send this to /proc/self/fd/1, it never appears'; \
		echo 'access.log = /proc/self/fd/2'; \
		echo; \
		echo 'clear_env = no'; \
		echo; \
		echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
		echo 'catch_workers_output = yes'; \
		echo 'decorate_workers_output = no'; \
	} | tee php-fpm.d/docker.conf; \
	{ \
		echo '[global]'; \
		echo 'daemonize = no'; \
		echo; \
		echo '[www]'; \
		echo 'listen = 9000'; \
		echo 'listen.mode = 0666'; \
	} | tee php-fpm.d/zz-docker.conf; \
	sed -ri 's!^user = .+!user = docker!; s!^group = .+!group = docker!' php-fpm.d/www.conf

# Override stop signal to stop process gracefully
# https://github.com/php/php-src/blob/17baa87faddc2550def3ae7314236826bc1b1398/sapi/fpm/php-fpm.8.in#L163
STOPSIGNAL SIGQUIT

# Extensions previously provided by php:8.4-fpm-bookworm plus the Drupal set.
# ftp is already compiled into the binary with openssl, so ftp_ssl_connect()
# exists and a second shared ftp build is not installed.
# gd keeps AVIF support from the previous 8.4 image.
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		default-mysql-client \
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
	docker-php-ext-install -j"$(nproc)" \
		bz2 \
		gd \
		intl \
		opcache \
		pdo \
		pdo_mysql \
		pdo_pgsql \
		soap \
		sockets \
		zip; \
	yes '' | pecl install apcu gnupg memcached imagick; \
	pecl clear-cache; \
	docker-php-ext-enable apcu gnupg memcached imagick; \
	ln -sf /usr/bin/mysqldump /usr/bin/mariadb-dump || true; \
	apt-get clean; \
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

EXPOSE 80
CMD ["/start.sh"]
