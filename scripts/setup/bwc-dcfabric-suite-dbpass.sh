#! /bin/bash

set -eu

BROCADE_INSTALL_DIR="/opt/brocade"
BWC_SVC_NAME="bwc-topology"
BWC_INSTALL_DIR="${BROCADE_INSTALL_DIR}/${BWC_SVC_NAME}"
BWC_LOG_DIR="/var/log/brocade/bwc"
BWC_CONFIG_DIR="/etc/brocade/bwc"
BWC_CONFIG_FILE="${BWC_CONFIG_DIR}/bwc-topology-service.conf"
BWC_DB_SETUP_SCRIPT="${BWC_INSTALL_DIR}/bin/bwc_topology_db_setup.sh"
BWC_DB_PASSWORD=""

function service_manager() {
  local svcname=$1 action=$2
  if [ -d /run/systemd/system ]; then
    # systemd is running
    sudo systemctl $action $svcname
  elif [ $(cat /proc/1/comm) = init ] && (/sbin/initctl version 2>/dev/null | grep -q upstart) &&
          [ -f /etc/init/${svcname}.conf ]; then
    # init is running, and is upstart and service config is available
    # ! upstart running detection is a MUST, since upstart can be just
    # ! installed on a platform but not used (ex: docker container, centos).
    sudo /sbin/initctl $action $svcname
  elif command -v service > /dev/null 2>&1; then
    sudo service $svcname $action
  elif [ -x /etc/init.d/${1} ]; then
    sudo /etc/init.d/$svcname $action
  else
    echo -e "\e[31mError: Unknown service manager, we ONLY support systemd, upstart and sysv! \e[0m\n"
    exit 1
  fi
}

setup_args() {
  for i in "$@"
    do
      case $i in
          --bwc-db-password=*)
          BWC_DB_PASSWORD="${i#*=}"
          shift
          ;;
          *)
          # unknown option
          ;;
      esac
    done

    if [[ -z "${BWC_DB_PASSWORD}" ]]; then
        >&2 echo "ERROR: The --bwc-db-password option is not provided. Please provide a password to set for db access."
        exit 1
    fi
}

echo "INFO: Parsing script input args..."
setup_args $@

echo "INFO: Ensuring ${BWC_SVC_NAME} service is not running..."
service_manager ${BWC_SVC_NAME} stop || true

if [ ! -e "${BWC_CONFIG_FILE}" ]; then
    >&2 echo "ERROR: The config file \"${BWC_CONFIG_FILE}\" does not exists."
    exit 1
fi

echo "INFO: Replacing the DB password in the connection string at the config file \"${BWC_CONFIG_FILE}\"..."
sudo sed -i -e "s/\(^connection\s*=\s*['\"]\?postgresql:\/\/.*:\).*\(@.*\)/\1${BWC_DB_PASSWORD}\2/" ${BWC_CONFIG_FILE}
