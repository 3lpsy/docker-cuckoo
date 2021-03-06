#!/bin/sh

set -e

setDefaults() {
  export MONGO_HOST=${MONGO_HOST:="$(env | grep MONGO.*PORT_.*_TCP_ADDR= | sed -e 's|.*=||')"}
  export MONGO_TCP_PORT=${MONGO_TCP_PORT:="$(env | grep MONGO.*PORT_.*_TCP_PORT= | sed -e 's|.*=||')"}
  export POSTGRES_HOST=${POSTGRES_HOST:="$(env | grep POSTGRES.*PORT_.*_TCP_ADDR= | sed -e 's|.*=||')"}
  export POSTGRES_TCP_PORT=${POSTGRES_TCP_PORT:="$(env | grep POSTGRES.*PORT_.*_TCP_PORT= | sed -e 's|.*=||')"}
  env | grep -E "^MONGO_HOST|^MONGO_TCP_PORT|^POSTGRES.*|^RESULTSERVER" | sort -n
}

# Wait for. Params: host, port, service
waitFor() {
    echo -n "===> Waiting for ${3}(${1}:${2}) to start..."
    i=1
    while [ $i -le 20 ]; do
        if nc -vz ${1} ${2} 2>/dev/null; then
            echo "${3} is ready!"
            return 0
        fi

        echo -n '.'
        sleep 1
        i=$((i+1))
    done

    echo
    echo >&2 "${3} is not available"
    echo >&2 "Address: ${1}:${2}"
}

setUpCuckoo(){
  echo "===> Use default ports and hosts if not specified..."
  setDefaults
  echo
  echo "===> Update /cuckoo/conf/reporting.conf if needed..."
  /update_conf.py
  echo
  # Wait until all services are started
  if [ ! "$MONGO_HOST" == "" ]; then
  	waitFor ${MONGO_HOST} ${MONGO_TCP_PORT} MongoDB
  fi
  echo
  if [ ! "$POSTGRES_HOST" == "" ]; then
  	waitFor ${POSTGRES_HOST} ${POSTGRES_TCP_PORT} Postgres
  fi
}

# Add cuckoo as command if needed
if [ "${1:0:1}" = '-' ]; then
  setUpCuckoo
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo/

  set -- python cuckoo.py "$@"
fi

# Drop root privileges if we are running cuckoo-daemon
if [ "$1" = 'daemon' -a "$(id -u)" = '0' ]; then
  shift
  # If not set default to 0.0.0.0
  export RESULTSERVER=${RESULTSERVER:=0.0.0.0}
  setUpCuckoo
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo

  set -- su-exec cuckoo /sbin/tini -- python cuckoo.py "$@"

elif [ "$1" = 'submit' -a "$(id -u)" = '0' ]; then
  shift
  setUpCuckoo
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo/utils

  set -- su-exec cuckoo /sbin/tini -- python submit.py "$@"

elif [ "$1" = 'process' -a "$(id -u)" = '0' ]; then
  shift
  setUpCuckoo
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo/utils

  set -- su-exec cuckoo /sbin/tini -- python process.py "$@"

elif [ "$1" = 'api' -a "$(id -u)" = '0' ]; then
  setUpCuckoo
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo/utils

  set -- su-exec cuckoo /sbin/tini -- python api.py --host 0.0.0.0 --port 1337

elif [ "$1" = 'web' -a "$(id -u)" = '0' ]; then
  setUpCuckoo
  if [ -z "$MONGO_HOST" ]; then
    echo >&2 "[ERROR] MongoDB cannot be found. Please link mongo and try again..."
    exit 1
  fi
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo/web

  set -- su-exec cuckoo /sbin/tini -- python manage.py runserver 0.0.0.0:31337

elif [ "$1" = 'distributed' -a "$(id -u)" = '0' ]; then
  shift
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo/distributed

  set -- su-exec cuckoo /sbin/tini -- python app.py "$@"

elif [ "$1" = 'stats' -a "$(id -u)" = '0' ]; then
  shift
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo/utils

  set -- su-exec cuckoo /sbin/tini -- python stats.py "$@"

elif [ "$1" = 'help' -a "$(id -u)" = '0' ]; then
  setUpCuckoo
  # Change the ownership of /cuckoo to cuckoo
  chown -R cuckoo:cuckoo /cuckoo
  cd /cuckoo

  set -- su-exec cuckoo /sbin/tini -- python cuckoo.py --help
fi

exec "$@"
