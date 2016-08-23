#! /bin/bash

set -ue

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

BASE_PATH="https://raw.githubusercontent.com/StackStorm/bwc-installer"

NO_LICENSE_BANNER="
LICENSE KEY not provided. You'll need a license key to install Brocade Workflow Composer (BWC).
Please visit http://www.brocade.com/en/products-services/network-automation/workflow-composer.html
to purchase or trial BWC.

Please contact sales@brocade.com if you have any questions.
"

setup_args() {
  for i in "$@"
    do
      case $i in
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

  if [[ "$USERNAME" = '' || "$PASSWORD" = '' ]]; then
    USERNAME=${USERNAME:-st2admin}
    PASSWORD=${PASSWORD:-Ch@ngeMe}
    echo "You can use \"--user=<CHANGEME>\" and \"--password=<CHANGEME>\" to override following default st2 credentials."
    SLEEP_TIME=10
    echo "Username: ${USERNAME}"
    echo "Password: ${PASSWORD}"
    echo "Sleeping for ${SLEEP_TIME} seconds if you want to Ctrl + C now..."
    sleep ${SLEEP_TIME}
    echo "Resorting to default username and password... You have an option to change password later!"
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
  BWC_OS_INSTALLER="${BASE_PATH}/${BRANCH}/scripts/bwc-installer-el${RHMAJVER}.sh"
  BWC_OS_INSTALLER_FILE="bwc-installer-el${RHMAJVER}.sh"
elif [[ -n "$DEBTEST" ]]; then
  TYPE="debs"
  echo "*** Detected Distro is ${DEBTEST} ***"
  SUBTYPE=`lsb_release -a 2>&1 | grep Codename | grep -v "LSB" | awk '{print $2}'`
  echo "*** Detected flavor ${SUBTYPE} ***"
  if [[ "$SUBTYPE" != 'trusty' ]]; then
    echo "Unsupported ubuntu flavor ${SUBTYPE}. Please use 14.04 (trusty) as base system!"
    exit 2
  fi
  BWC_OS_INSTALLER="${BASE_PATH}/${BRANCH}/scripts/bwc-installer-deb.sh"
  BWC_OS_INSTALLER_FILE="bwc-installer-deb.sh"
else
  echo "Unknown Operating System"
  exit 2
fi

hash curl 2>/dev/null || { echo >&2 "'curl' is not installed. Aborting."; exit 1; }

ST2_CURL_TEST=`curl --output /dev/null --silent --head --fail ${ST2_COMMUNITY_INSTALLER}`
if [ $? -ne 0 ]; then
    echo -e "Could not find file ${ST2_COMMUNITY_INSTALLER}."
    exit 2
else
    echo "Downloading deployment script from: ${ST2_COMMUNITY_INSTALLER}"
    ST2_INSTALLER_FILE="st2-community-installer.sh"
    curl -SsL -o ${ST2_INSTALLER_FILE} ${ST2_COMMUNITY_INSTALLER}
    chmod +x ${ST2_INSTALLER_FILE}

    echo "Running deployment script for StackStorm Community Edition v${VERSION}..."
    echo "OS specific script cmd: bash ${ST2_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD}"
    bash ${ST2_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD}
fi


CURLTEST=`curl --output /dev/null --silent --head --fail ${BWC_OS_INSTALLER}`
if [ $? -ne 0 ]; then
    echo -e "Could not find file ${BWC_OS_INSTALLER}"
    exit 2
else
    echo "Downloading deployment script from: ${BWC_OS_INSTALLER}"
    curl -Ss -o ${BWC_OS_INSTALLER_FILE} ${BWC_OS_INSTALLER}
    chmod +x ${BWC_OS_INSTALLER_FILE}

    echo "Running deployment script for Brocade Workflow Composer v${VERSION}..."
    echo "OS specific script cmd: bash ${BWC_OS_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD}"
    bash ${BWC_OS_INSTALLER_FILE} ${VERSION} ${RELEASE} ${REPO_TYPE} ${USERNAME} ${PASSWORD}
fi
