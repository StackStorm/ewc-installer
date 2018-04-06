#!/bin/bash

set -u

ST2_COMMUNITY_INSTALLER='https://stackstorm.com/packages/install.sh'

DEBTEST=`lsb_release -a 2> /dev/null | grep Distributor | awk '{print $3}'`
RHTEST=`cat /etc/redhat-release 2> /dev/null | sed -e "s~\(.*\)release.*~\1~g"`
VERSION=''
RELEASE='stable'
REPO_TYPE=''
ST2_PKG_VERSION=''
USERNAME=''
PASSWORD=''
BRANCH='master'
LICENSE_KEY=''
SUITE=''

SUITES_LIST=(dcfabric-suite) # Space separated list of names that should map to package names.

# XXX: Once we have our S3 buckets set up, point these to public URLs.
BASE_PATH="https://raw.githubusercontent.com/StackStorm/bwc-installer"

# Ensure logging directory exists
sudo mkdir -p /var/log/st2

NO_LICENSE_BANNER="
LICENSE KEY not provided. You'll need a license key to install Extreme Workflow Composer (EWC).
Please visit  https://www.extremenetworks.com/product/workflow-composer/
to purchase or trial EWC.

For obtaining a subscription license, please contact us at ewc-team@extremenetworks.com
"

setup_args() {
  for i in "$@"
    do
      case $i in
          --suite=*)
          SUITE="${i#*=}"
          shift
          ;;
          -v|--version=*)
          VERSION="${i#*=}"
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

  if [ -z ${LICENSE_KEY} ]; then
    printf "${NO_LICENSE_BANNER}"
    exit 1
  else
    LICENSE_KEY_ARG="--license=${LICENSE_KEY}"
  fi

  if [[ "$VERSION" != '' ]]; then
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+dev$ ]]; then
      echo "$VERSION does not match supported formats x.y.z or x.ydev"
      exit 1
    fi

    if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+dev$ ]]; then
     echo "You're requesting a dev version! Switching to unstable!"
     RELEASE='unstable'
    fi
  fi

  REPO_NAME='enterprise'
  if [ "$REPO_TYPE" == "staging" ]; then
    REPO_NAME="staging-${REPO_NAME}"
  fi
  if [ "$RELEASE" == "unstable" ]; then
    REPO_NAME="${REPO_NAME}-unstable"
  fi

  hash curl 2>/dev/null || { echo >&2 "'curl' is not installed. Aborting."; exit 1; }

  # Check if provided license key is valid
  LICENSE_CHECK=`curl --head --silent --output /dev/null --fail --retry 3 "https://${LICENSE_KEY}:@packagecloud.io/install/repositories/StackStorm/${REPO_NAME}/script.deb.sh"`
  if [ $? -ne 0 ]; then
    echo -e "
      LICENSE: ${LICENSE_KEY} not valid.

      Please contact support@extremenetworks.com. Please include the SKU and the invalid license key in the email.
    "
    exit 2
  fi

  if [[ "$USERNAME" = '' || "$PASSWORD" = '' ]]; then
    USERNAME=${USERNAME:-st2admin}
    PASSWORD=${PASSWORD:-Ch@ngeMe}
    echo "You can use \"--user=<CHANGEME>\" and \"--password=<CHANGEME>\" to override following default st2 credentials."
    SLEEP_TIME=10
    echo "Username: ${USERNAME}"
    echo "Password: ****"
    echo "Sleeping for ${SLEEP_TIME} seconds if you want to Ctrl + C now..."
    sleep ${SLEEP_TIME}
    echo "Resorting to default username and password... You have an option to change password later!"
  fi

  if [ ! -z ${SUITE} ]; then
    if [[ $SUITES_LIST =~ $SUITE ]]; then
      SUITE="--suite=${SUITE}"
    else
      echo "${SUITE} is not a valid suite. Options are ${SUITES_LIST}."
      echo "Please re-run with --suite=<SUITE> with one of the valid suites listed above."
      exit 1
    fi
  fi
}

setup_args $@

get_version_branch() {
  if [[ "$RELEASE" == 'stable' ]]; then
      BRANCH="v$(echo ${VERSION} | awk 'BEGIN {FS="."}; {print $1 "." $2}')"
  fi
}

adddate() {
  while IFS= read -r line; do
    echo "$(date +%Y%m%dT%H%M%S%z) $line"
  done
}

# Check if .deb package(s) is installed
deb_is_installed() {
  expected_packages=$(echo $@ | awk '{print NF}')
  installed_packages=$(dpkg-query -W -f='${Status}\n' $@ 2>/dev/null | grep -c 'install ok installed')

  [[ "$expected_packages" == "$installed_packages" ]]
}

# Check if .rpm package(s) is installed
rpm_is_installed() {
  rpm -q --quiet $@
}

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
  PKG_TYPE="rpm"
  echo "*** Detected Distro is ${RHTEST} ***"
  RHMAJVER=`cat /etc/redhat-release | sed 's/[^0-9.]*\([0-9.]\).*/\1/'`
  echo "*** Detected distro version ${RHMAJVER} ***"
  if [[ "$RHMAJVER" != '6' && "$RHMAJVER" != '7' ]]; then
    echo "Unsupported distro version $RHMAJVER! Aborting!"
    exit 2
  fi
  BWC_OS_INSTALLER="${BASE_PATH}/${BRANCH}/scripts/bwc-installer-el${RHMAJVER}.sh"
  BWC_OS_INSTALLER_FILE="bwc-installer-el${RHMAJVER}.sh"
elif [[ -n "$DEBTEST" ]]; then
  PKG_TYPE="deb"
  echo "*** Detected Distro is ${DEBTEST} ***"
  SUBTYPE=`lsb_release -a 2>&1 | grep Codename | grep -v "LSB" | awk '{print $2}'`
  echo "*** Detected flavor ${SUBTYPE} ***"
  if [[ "$SUBTYPE" != 'trusty' && "$SUBTYPE" != 'xenial' ]]; then
    echo "Unsupported ubuntu flavor ${SUBTYPE}. Please use 14.04 (trusty) or 16.04 (xenial) as base system!"
    exit 2
  fi
  BWC_OS_INSTALLER="${BASE_PATH}/${BRANCH}/scripts/bwc-installer-deb.sh"
  BWC_OS_INSTALLER_FILE="bwc-installer-deb.sh"
else
  echo "Unknown Operating System"
  exit 2
fi


if ${PKG_TYPE}_is_installed st2 st2mistral; then
    echo 'StackStorm Community version is already installed.'
    echo 'Proceeding with EWC Enterprise install ...'
elif ! curl --output /dev/null --silent --fail ${ST2_COMMUNITY_INSTALLER}; then
    echo -e "Could not find file ${ST2_COMMUNITY_INSTALLER}."
    exit 2
else
    echo "Downloading deployment script from: ${ST2_COMMUNITY_INSTALLER}"
    ST2_INSTALLER_FILE="st2-community-installer.sh"
    curl -SsL -o ${ST2_INSTALLER_FILE} ${ST2_COMMUNITY_INSTALLER}
    chmod +x ${ST2_INSTALLER_FILE}

    echo "Running deployment script for StackStorm Community Edition ${VERSION}..."
    echo "OS specific script cmd: bash ${ST2_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} --password=****"
    bash ${ST2_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD}
    if [ $? -ne 0 ]; then
      echo "StackStorm community version failed to install."
      echo "Please contact support@extremenetworks.com with installation logs if you have any questions."
      exit 1
    fi
    echo "StackStorm Community version installed successfully."
fi


if [ ! -z ${SUITE} ] && ${PKG_TYPE}_is_installed bwc-enterprise bwc-ui; then
    echo 'EWC Enterprise is already installed.'
    echo 'Proceeding with EWC Automation Suites install ...'
elif ! curl --output /dev/null --silent --fail ${BWC_OS_INSTALLER}; then
    echo -e "Could not find file ${BWC_OS_INSTALLER}"
    exit 2
else
    echo "Downloading deployment script from: ${BWC_OS_INSTALLER}"
    curl -Ss -o ${BWC_OS_INSTALLER_FILE} ${BWC_OS_INSTALLER}
    chmod +x ${BWC_OS_INSTALLER_FILE}

    echo "Running deployment script for Extreme Workflow Composer ${VERSION}..."
    echo "OS specific script cmd: bash ${BWC_OS_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} --password=**** --license=****"
    TS=$(date +%Y%m%dT%H%M%S)
    bash ${BWC_OS_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD} ${LICENSE_KEY_ARG} 2>&1 | adddate | sudo tee /var/log/st2/bwc-install.${TS}.log
    rc=${PIPESTATUS[0]}
    if [ ${rc} -ne 0 ]; then
      echo "EWC Enterprise failed to install."
      echo "Please contact support@extremenetworks.com with installation logs if you have any questions."
      exit 2
    fi
fi

if [[ "${SUITE_VERSION:-}" != '' ]]; then
  VERSION="--version=${SUITE_VERSION}"
fi

SUITE_INSTALLER_FILE='bwc-suite-installer.sh'
SUITE_INSTALLER="${BASE_PATH}/${BRANCH}/scripts/bwc-suite-installer.sh"

if [ ! -z ${SUITE} ]; then
  CURLTEST=`curl --output /dev/null --silent --fail ${SUITE_INSTALLER}`
  if [ $? -ne 0 ]; then
      echo -e "Could not find file ${SUITE_INSTALLER}"
      exit 2
  else
      echo "Downloading deployment script from: ${SUITE_INSTALLER}"
      curl -Ss -o ${SUITE_INSTALLER_FILE} ${SUITE_INSTALLER}
      chmod +x ${SUITE_INSTALLER_FILE}

      echo "Running deployment script for EWC Automation Suites ${VERSION}..."
      echo "OS specific script cmd: bash ${SUITE_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} --password=**** --license=**** ${SUITE}"
      TS=$(date +%Y%m%dT%H%M%S)
      bash ${SUITE_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD} ${LICENSE_KEY_ARG} ${SUITE} 2>&1 | adddate | sudo tee /var/log/st2/bwc-suite-install.${TS}.log
      rc=${PIPESTATUS[0]}
      if [ ${rc} -ne 0 ]; then
        echo "EWC Automation Suites failed to install."
        echo "Please contact support@extremenetworks.com with installation logs if you have any questions."
        exit 3
      fi
  fi
fi
