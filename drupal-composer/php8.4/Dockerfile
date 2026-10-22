FROM php:8.4.27-cli-alpine

LABEL maintainer="jason@ciandt.com"

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN apk upgrade --update && apk add --no-cache \
      git \
      openssh-client \
      patch \
      icu-dev \
      libjpeg-turbo-dev \
      libpng-dev \
      libzip-dev \
      zip \
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install gd pdo pdo_mysql zip intl
