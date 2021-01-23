#!/bin/bash

set -x

if [ "$#" -ne 1 ]; then
    echo "usage: <init_db|import|run>"
    echo "commands:"
    echo "    init_db: Set up the database"
    echo "    import: Import /data.osm.pbf and low-zoom shapes"
    echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    echo "    UPDATES: consecutive updates (enabled/disabled)"
    exit 1
fi

if [ "$1" = "debug" ]; then
  bash
  exit 0
fi

if [ "$1" = "init_db" ]; then
  service postgresql start

  sudo -u postgres psql -c "CREATE USER renderaccount WITH PASSWORD 'renderaccount';"
  sudo -u postgres psql -c "ALTER ROLE renderaccount SUPERUSER;"
  sudo -u postgres createdb -E UTF8 -O renderaccount gis
  sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
  sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
  sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderaccount;"
  sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderaccount;"

  service postgresql stop

  exit 0
fi

if [ "$1" = "import" ]; then
    service postgresql start

    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data.osm.pbf ] && [ -z "$DOWNLOAD_PBF" ]; then
        echo "WARNING: No import file at /data.osm.pbf, so importing Luxembourg as example..."
        DOWNLOAD_PBF="https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
        DOWNLOAD_POLY="https://download.geofabrik.de/europe/luxembourg.poly"
    fi

    if [ -n "$DOWNLOAD_PBF" ]; then
        echo "INFO: Download PBF file: $DOWNLOAD_PBF"
        wget "$WGET_ARGS" "$DOWNLOAD_PBF" -O /data.osm.pbf
        if [ -n "$DOWNLOAD_POLY" ]; then
            echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
            wget "$WGET_ARGS" "$DOWNLOAD_POLY" -O /var/lib/mod_tile/data.poly
        fi
    fi

    # Import data
    sudo -u renderaccount osm2pgsql -d gis --create --slim -G --hstore --tag-transform-script /opt/openstreetmap-carto/openstreetmap-carto.lua --number-processes 1 -S /opt/openstreetmap-carto/openstreetmap-carto.style /data.osm.pbf ${OSM2PGSQL_EXTRA_ARGS}

    # Get low-zoom stuff
    cd /opt/openstreetmap-carto
    sudo -u renderaccount scripts/get-external-data.py

    # Create indexes
    sudo -u postgres psql -d gis -f indexes.sql

    # Register that data has changed for mod_tile caching purposes
    touch /var/lib/mod_tile/planet-import-complete

    exit 0
fi

if [ "$1" = "run" ]; then
    rm -rf /tmp/*

    service postgresql start
    service apache2 restart

    # Run while handling docker stop's SIGTERM
    stop_handler() {
        kill -TERM "$child"
    }
    trap stop_handler SIGTERM

    mkdir -p /var/run/renderd
    chown renderaccount /var/run/renderd

    sudo -u renderaccount renderd -f -c /usr/local/etc/renderd.conf &
    child=$!
    wait "$child"

    service apache2 stop
    service postgresql stop

    exit 0
fi

echo "invalid command"
exit 1
