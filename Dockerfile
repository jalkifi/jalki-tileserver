FROM ubuntu:20.04

# Set up environment
ENV TZ=UTC
ENV AUTOVACUUM=on
ENV UPDATES=disabled
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezo

RUN apt-get update && apt-get install -y sudo libboost-all-dev git tar unzip wget bzip2 build-essential autoconf libtool libxml2-dev libgeos-dev libgeos++-dev libpq-dev libbz2-dev libproj-dev munin-node munin protobuf-c-compiler libfreetype6-dev libtiff5-dev libicu-dev libgdal-dev libcairo2-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua5.2-dev ttf-unifont lua5.1 liblua5.1-0-dev osm2pgsql autoconf apache2-dev libtool libxml2-dev libbz2-dev libgeos-dev libgeos++-dev libproj-dev gdal-bin libmapnik-dev mapnik-utils python3-mapnik python3-psycopg2 python3-yaml python3-requests npm fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted ttf-unifont

RUN npm install -g carto

# Run this before installing postgresql!
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

RUN apt-get install -y postgresql postgresql-contrib postgis postgresql-12-postgis-3 postgresql-12-postgis-3-scripts

# mod_tile
RUN mkdir -p /root/src \
 && cd /root/src \
 && git clone -b switch2osm git://github.com/SomeoneElseOSM/mod_tile.git \
 && cd mod_tile \
 && ./autogen.sh \
 && ./configure \
 && make \
 && make install \
 && make install-mod_tile \
 && ldconfig \
 && mkdir -p /var/lib/mod_tile
COPY renderd.conf /usr/local/etc/renderd.conf

# Apache
RUN mkdir /var/run/renderd \
 && echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf \
 && a2enconf mod_tile
COPY apache.conf /etc/apache2/sites-available/000-default.conf
ENV APACHE_LOG_DIR /var/local/log

# Renderaccount
RUN adduser --disabled-password --gecos "" renderaccount
RUN chgrp renderaccount /opt && chmod g+w /opt && chgrp renderaccount /var/lib/mod_tile && chmod g+w /var/lib/mod_tile

# CartoCSS styles
RUN cd /opt \
  && git clone git://github.com/mhaulo/jalki-openstreetmap-carto.git openstreetmap-carto \
  && cd openstreetmap-carto \
  && carto project.mml > mapnik.xml \
  && chown -R renderaccount.renderaccount /opt/openstreetmap-carto

COPY run.sh /
COPY indexes.sql /
COPY Procfile /

ENTRYPOINT ["/run.sh"]
CMD []
EXPOSE 80
