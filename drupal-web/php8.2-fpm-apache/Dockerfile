FROM debian:bullseye-slim

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

# persistent / runtime deps
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		$PHPIZE_DEPS \
		ca-certificates \
		curl \
		xz-utils \
		exim4;

RUN groupadd -r -g 1001 docker && useradd --no-log-init -r -u 1000 -g docker docker

ENV PHP_INI_DIR /usr/local/etc/php
RUN set -eux; \
	mkdir -p "$PHP_INI_DIR/conf.d"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
	[ ! -d /var/www/html ]; \
	mkdir -p /var/www/html; \
	chown docker:docker /var/www/html; \
	chmod 777 /var/www/html

# Install apache2
ENV APACHE_CONFDIR /etc/apache2
ENV APACHE_ENVVARS $APACHE_CONFDIR/envvars

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

# Apache + PHP requires preforking Apache for best results
RUN a2enmod mpm_event && a2dismod mpm_prefork
RUN a2enmod proxy proxy_fcgi proxy_http

# PHP files should be handled by PHP, and should be preferred over any other file type
RUN { \
		echo '<FilesMatch \.php$>'; \
		echo '\tSetHandler "proxy:fcgi://127.0.0.1:9000"'; \
#	echo '\tSetHandler "proxy:unix:/var/run/php7.4-fpm.sock|fcgi://localhost/"'; \
		echo '</FilesMatch>'; \
		echo; \
		echo 'DirectoryIndex disabled'; \
		echo 'DirectoryIndex index.php index.html'; \
		echo; \
		echo '<Directory /var/www/>'; \
		echo '\tOptions -Indexes'; \
		echo '\tAllowOverride All'; \
		echo '</Directory>'; \
	} | tee "$APACHE_CONFDIR/conf-available/docker-php.conf" \
	&& a2enconf docker-php

ENV PHP_EXTRA_BUILD_DEPS apache2-dev
#ENV PHP_EXTRA_CONFIGURE_ARGS --with-apxs2 --disable-cgi
ENV PHP_EXTRA_CONFIGURE_ARGS --enable-fpm --with-fpm-user=docker --with-fpm-group=docker --disable-cgi

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# https://github.com/docker-library/php/issues/272
# -D_LARGEFILE_SOURCE and -D_FILE_OFFSET_BITS=64 (https://www.php.net/manual/en/intro.filesystem.php)
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

ENV GPG_KEYS 1198C0117593497A5EC5C199286AF1F9897469DC 39B641343D8C104B2B146DC3F9C39DC0B9698544 E60913E4DF209907D8E30D96659A97C9CF2A795A

ENV PHP_VERSION 8.2.35
ENV PHP_URL="https://www.php.net/distributions/php-8.2.35.tar.xz" PHP_ASC_URL="https://www.php.net/distributions/php-8.2.35.tar.xz.asc"
ENV PHP_SHA256="5737b98601fe5ab1b8c5db0c82ed3158acb9283ed3081ffe2faffb9ac81455e6"

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
			gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key"; \
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
		--with-fpm-user=www-data \
		--with-fpm-group=www-data \
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
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
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
#	echo 'listen = /var/run/php7.4-fpm.sock'; \
		echo 'listen.mode = 0666'; \
	} | tee php-fpm.d/zz-docker.conf

# Override stop signal to stop process gracefully
# https://github.com/php/php-src/blob/17baa87faddc2550def3ae7314236826bc1b1398/sapi/fpm/php-fpm.8.in#L163
STOPSIGNAL SIGQUIT

ENV DRUSH_VERSION 8.4.10
ENV DRUSH_LAUNCHER_VERSION 0.10.1
ENV DRUSH_LAUNCHER_FALLBACK "/usr/local/drush/drush"
ENV MEMCACHED_VERSION 3.1.5

# Install necessary packages and PHP extensions for both Drupal 8
# Drupal 8 PHP requirement: https://www.drupal.org/docs/8/system-requirements/php-requirements
RUN a2enmod rewrite \
  && apt-get update && apt-get install -y --no-install-recommends \
      mariadb-client \
      libpng-dev \
      libjpeg62-turbo-dev \
      libfreetype6-dev \
      libpq-dev \
      libxml2-dev \
      nano \
      libmemcached-dev \
      rsyslog \
      zip \
      libzip-dev \
      libbz2-dev \
      libmagickwand-dev \
      libwebp-dev \
	&& docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp\
  && docker-php-ext-install -j "$(nproc)" gd \
  && docker-php-ext-configure zip \
  && docker-php-ext-install zip \
  && docker-php-ext-install bz2 \
	&& docker-php-ext-install pdo pdo_mysql pdo_pgsql zip opcache sockets soap \
	# Install Intl PHP extension
	&& docker-php-ext-configure intl \
	&& docker-php-ext-install intl \
  # Install Memcached PHP extension
  && curl -L -o /tmp/memcached.tar.gz "https://github.com/php-memcached-dev/php-memcached/archive/v$MEMCACHED_VERSION.tar.gz" \
  && mkdir -p /usr/src/php/ext/memcached \
  && tar -C /usr/src/php/ext/memcached -zxvf /tmp/memcached.tar.gz --strip 1 \
  && docker-php-ext-configure memcached \
  && docker-php-ext-install memcached \
  # Clean up
  && rm /tmp/memcached.tar.gz \
	&& apt-get clean && rm -rf /var/lib/apt/lists/* \
  # Configure Apache web docroot
  && sed -i 's/\/var\/www\/html/\/var\/www\/html\/docroot/g' /etc/apache2/sites-available/000-default.conf \
  # Remove old Apache ServerTokens & ServerSignature
  && sed -i "/^ServerTokens/d; /^ServerSignature/d" /etc/apache2/apache2.conf \
  # Add new Apache ServerTokens & ServerSignature
  && echo 'ServerTokens Prod\nServerSignature Off' >> /etc/apache2/apache2.conf

COPY config/php.ini /usr/local/etc/php/conf.d/

COPY config/rsyslog.conf /etc/rsyslog.conf

# Install imagick
RUN printf "\n" | pecl install imagick
RUN docker-php-ext-enable imagick

# Install apcu
RUN printf "\n" | pecl install apcu
RUN docker-php-ext-enable apcu
RUN pecl clear-cache

# Install new relic agent
RUN curl -o newrelic.tar.gz https://download.newrelic.com/php_agent/release/newrelic-php5-12.6.0.34-linux.tar.gz \
  && gzip -dc newrelic.tar.gz | tar xf - \
  && cd newrelic-php5-12.6.0.34-linux \
  && NR_INSTALL_USE_CP_NOT_LN=1 NR_INSTALL_SILENT=1 ./newrelic-install install \
  && rm -rf ../newrelic-php5-12.6.0.34-linux newrelic.tar.gz \
  && sed -i \
           -e 's/;newrelic.enabled =.*/newrelic.enabled = false/' \
           -e 's/;newrelic.daemon.dont_launch =.*/newrelic.daemon.dont_launch = 3/' \
           /usr/local/etc/php/conf.d/newrelic.ini

# Install Composer
# COPY --from=composer /usr/bin/composer /usr/bin/composer

# Add default user `docker` and modify user id and group id
RUN echo '#!/bin/bash\nset -e\n\
[[ $(id -u docker) != ${CURRENT_USER_UID:-1000} ]] && usermod -u ${CURRENT_USER_UID:-1000} docker\n\
[[ $(id -g docker) != ${CURRENT_USER_GID:-1001} ]] && groupmod -g ${CURRENT_USER_GID:-1001} docker\n\
chown -R docker:docker /var/www/html\n\
nohup rsyslogd -n -f /etc/rsyslog.conf &\n\
service exim4 start\n\
php-fpm -D\n\
apache2-foreground' > /start.sh && chmod 755 /start.sh \
  # Install Drush
  && mkdir -p /usr/local/drush \
  && curl -fsSL -o /usr/local/drush/drush "https://github.com/drush-ops/drush/releases/download/$DRUSH_VERSION/drush.phar" \
  && curl -fsSL -o /usr/local/bin/drush https://github.com/drush-ops/drush-launcher/releases/download/${DRUSH_LAUNCHER_VERSION}/drush.phar \
  && chmod +x /usr/local/drush/drush /usr/local/bin/drush \
  && drush --version

EXPOSE 80

CMD ["/start.sh"]
