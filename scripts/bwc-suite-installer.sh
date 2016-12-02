#! /bin/bash

set -u

DEBTEST=`lsb_release -a 2> /dev/null | grep Distributor | awk '{print $3}'`
RHTEST=`cat /etc/redhat-release 2> /dev/null | sed -e "s~\(.*\)release.*~\1~g"`
VERSION=''
RELEASE='stable'
REPO_TYPE=''
USERNAME=''
PASSWORD=''
BRANCH='master'
LICENSE_KEY=''

SUITES_LIST=(bwc-ipfabric-suite) # Space separated list of names that should map to package names.

# XXX: Once we have our S3 buckets set up, point these to public URLs.
BASE_PATH="https://raw.githubusercontent.com/StackStorm/bwc-installer"

SUITE=''

fail() {
  echo "############### ERROR ###############"
  echo "# Failed on step - $STEP #"
  echo "#####################################"
  exit 2
}

setup_args() {
  for i in "$@"
    do
      case $i in
          --suite=*)
          SUITE="${i#*=}"
          shift
          ;;
          -s|--stable)
          RELEASE=stable
          shift
          ;;
          -u|--unstable)
          RELEASE=unstable
          shift
          ;;
          --staging)
          REPO_TYPE='staging'
          shift
          ;;
          -v|--version=*)
          VERSION="${i#*=}"
          shift
          ;;
          --user=*)
          USERNAME="${i#*=}"
          shift
          ;;
          --password=*)
          PASSWORD="${i#*=}"
          shift
          ;;
          --license=*)
          LICENSE_KEY="${i#*=}"
          shift
          ;;
          *)
          # unknown option
          ;;
      esac
    done

  if [[ $SUITES_LIST =~ $SUITE ]]; then
    echo "" # Nothing to do
  else
    echo "${SUITE} is not a valid suite. Options are ${SUITES_LIST}."
    echo "Please re-run with --suite=<SUITE> with one of the valid suites listed above."
    exit 1
  fi

  if [ -z ${LICENSE_KEY} ]; then
    printf "${NO_LICENSE_BANNER}"
    exit 1
  else
    LICENSE_KEY="--license=${LICENSE_KEY}"
  fi

  if [[ "$USERNAME" = '' || "$PASSWORD" = '' ]]; then
    echo "This script requires Brocade Workflow Composer credentials (Username/Password) to run."
    echo "Please re-run script with --user=<USER> --password=<PASSWORD> arguments."
    exit 1
  fi
}

setup_args $@

if [[ "$VERSION" != '' ]]; then
  get_version_branch $VERSION
  VERSION="--version=${VERSION}"
fi

if [[ "$RELEASE" != '' ]]; then
  RELEASE="--${RELEASE}"
fi

if [[ "$REPO_TYPE" == 'staging' ]]; then
  REPO_TYPE="--staging"
fi

USERNAME="--user=${USERNAME}"
PASSWORD="--password=${PASSWORD}"

if [[ -n "$RHTEST" ]]; then
  TYPE="rpms"
  echo "*** Detected Distro is ${RHTEST} ***"
  RHMAJVER=`cat /etc/redhat-release | sed 's/[^0-9.]*\([0-9.]\).*/\1/'`
  echo "*** Detected distro version ${RHMAJVER} ***"
  if [[ "$RHMAJVER" != '6' && "$RHMAJVER" != '7' ]]; then
    echo "Unsupported distro version $RHMAJVER! Aborting!"
    exit 2
  fi
  SUITE_OS_INSTALLER="${BASE_PATH}/${BRANCH}/scripts/${SUITE}-installer-el${RHMAJVER}.sh"
  SUITE_OS_INSTALLER_FILE="${SUITE}-installer-el${RHMAJVER}.sh"
elif [[ -n "$DEBTEST" ]]; then
  TYPE="debs"
  echo "*** Detected Distro is ${DEBTEST} ***"
  SUBTYPE=`lsb_release -a 2>&1 | grep Codename | grep -v "LSB" | awk '{print $2}'`
  echo "*** Detected flavor ${SUBTYPE} ***"
  if [[ "$SUBTYPE" != 'trusty' && "$SUBTYPE" != 'xenial' ]]; then
    echo "Unsupported ubuntu flavor ${SUBTYPE}. Please use 14.04 (trusty) or 16.04 (xenial) as base system!"
    exit 2
  fi
  SUITE_OS_INSTALLER="${BASE_PATH}/${BRANCH}/scripts/${SUITE}-installer-deb.sh"
  SUITE_OS_INSTALLER_FILE="${SUITE}-installer-deb.sh"
else
  echo "Unknown Operating System"
  exit 2
fi

hash curl 2>/dev/null || { echo >&2 "'curl' is not installed. Aborting."; exit 1; }

CURLTEST=`curl --output /dev/null --silent --head --fail ${SUITE_OS_INSTALLER}`
if [ $? -ne 0 ]; then
    echo -e "Could not find file ${SUITE_OS_INSTALLER}"
    exit 2
else
    echo "Downloading deployment script from: ${SUITE_OS_INSTALLER}"
    curl -Ss -o ${SUITE_OS_INSTALLER_FILE} ${SUITE_OS_INSTALLER}
    chmod +x ${SUITE_OS_INSTALLER_FILE}

    echo "Running deployment script for Brocade Workflow Composer ${VERSION}..."
    echo "OS specific script cmd: bash ${SUITE_OS_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD}"
    bash ${SUITE_OS_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD} ${LICENSE_KEY}
fi
