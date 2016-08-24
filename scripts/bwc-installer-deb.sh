#!/bin/bash

set -eu

VERSION=''
RELEASE='stable'
REPO_TYPE=''
REPO_PREFIX=''
USERNAME=''
PASSWORD=''
LICENSE_KEY=''

SETUP_SCRIPTS_BASE_PATH="https://raw.githubusercontent.com/StackStorm/bwc-installer/scripts/setup/"

NO_LICENSE_BANNER="
LICENSE KEY not provided. You'll need a license key to install Brocade Workflow Composer (BWC).
Please visit http://www.brocade.com/en/products-services/network-automation/workflow-composer.html
to purchase or trial BWC.

Please contact sales@brocade.com if you have any questions.
"

BWC_ENTERPRISE_VERSION=''
IPFABRIC_SUITE_VERSION=''

REPO_NAME='enteprise'

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

  if [[ "$REPO_TYPE" != '' ]]; then
      REPO_PREFIX="${REPO_TYPE}-"
  fi

  if [[ "$VERSION" != '' ]]; then
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+dev$ ]]; then
      echo "$VERSION does not match supported formats x.y.z or x.ydev"
      exit 1
    fi

    if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+dev$ ]]; then
      echo "You're requesting a dev version! Switching to unstable!"
      RELEASE='unstable'
      REPO_NAME='enteprise-unstable'
    fi
  fi

  echo "########################################################"
  echo "          Installing BWC $RELEASE $VERSION              "
  echo "########################################################"

  if [ "$REPO_TYPE" == "staging" ]; then
    printf "\n\n"
    echo "################################################################"
    echo "### Installing from staging repos!!! USE AT YOUR OWN RISK!!! ###"
    echo "################################################################"
    REPO_NAME='staging-enterprise'
  fi

  if [[ "$USERNAME" = '' || "$PASSWORD" = '' ]]; then
    echo "Let's set StackStorm admin credentials."
    echo "You can also use \"--user\" and \"--password\" for unattended installation."
    echo "Press \"ENTER\" to continue or \"CTRL+C\" to exit/abort"
    read -e -p "Admin username: " -i "st2admin" USERNAME
    read -e -s -p "Password: " PASSWORD
  fi
}

setup_package_cloud_repo() {
  curl -s https://${LICENSE_KEY:}packagecloud.io/install/repositories/StackStorm/${REPO_NAME}/script.deb.sh | sudo bash
}

get_full_pkg_versions() {
  if [ "$VERSION" != '' ];
  then
    local IPF_VER=$(apt-cache show bwc-ipfabric-suite | grep Version | awk '{print $2}' | grep $VERSION | sort --version-sort | tail -n 1)
    if [ -z "$IPF_VER" ]; then
      echo "Could not find requested version of bwc-ipfabric-suite!!!"
      sudo apt-cache policy bwc-ipfabric-suite
      exit 3
    fi

    local BWC_VER=$(apt-cache show bwc-enterprise | grep Version | awk '{print $2}' | grep $VERSION | sort --version-sort | tail -n 1)
    if [ -z "$BWC_VER" ]; then
      echo "Could not find requested version of bwc-enterprise!!!"
      sudo apt-cache policy bwc-enterprise
      exit 3
    fi

    BWC_ENTERPRISE_VERSION="=${BWC_VER}"
    IPFABRIC_SUITE_VERSION="=${IPF_VER}"
    echo "##########################################################"
    echo "#### Following versions of packages will be installed ####"
    echo "bwc-enterprise${BWC_ENTERPRISE_VERSION}"
    echo "bwc-ipfabric-suite${IPFABRIC_SUITE_VERSION}"
    echo "##########################################################"
  fi
}

install_bwc_enterprise() {
  sudo apt-get update
  sudo apt-get -y install bwc-enterprise${BWC_ENTERPRISE_VERSION}
}

install_ipfabric_automation_suite() {
  sudo apt-get -y install bwc-ipfabric-suite${IPFABRIC_SUITE_VERSION}
}

setup_ipfabric_automation_suite() {
  local IPFABRIC_SETUP_SCRIPT="${SETUP_SCRIPTS_BASE_PATH}/bwc-ipfabric-suite-setup.sh"
  local IPFABRIC_SETUP_FILE="bwc-ipfabric-suite-setup.sh"
  CURLTEST=`curl --output /dev/null --silent --head --fail ${IPFABRIC_SETUP_SCRIPT}`
  if [ $? -ne 0 ]; then
    echo -e "Could not find file ${BWC_OS_INSTALLER}"
    exit 2
  else
    echo "Downloading ipfabric setup script from: ${IPFABRIC_SETUP_SCRIPT}"
    curl -Ss -o ${IPFABRIC_SETUP_FILE} ${IPFABRIC_SETUP_SCRIPT}
    chmod +x ${IPFABRIC_SETUP_FILE}

    echo "Running deployment script for Brocade Workflow Composer ${VERSION}..."
    echo "Generating DB password for bwc-topology postgres database"
    local DB_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
    echo "OS specific script cmd: bash ${IPFABRIC_SETUP_FILE} --bwc-db-password=${DB_PASSWORD}"

    local ST2_AUTH_TOKEN=$(st2 auth ${USERNAME} -p ${PASSWORD} -t)
    ST2_AUTH_TOKEN=${ST2_AUTH_TOKEN} bash -c "${IPFABRIC_SETUP_FILE} --bwc-db-password=${DB_PASSWORD}"
  fi
}

ok_message() {

cat << "EOF"
                                 )        )
   (    (  (        (         ( /(     ( /(
 ( )\   )\))(   '   )\        )\())    )\())
 )((_) ((_)()\ )  (((_)      ((_)\   |((_)\
((_)_  _(())\_)() )\___        ((_)  |_ ((_)
 | _ ) \ \((_)/ /((/ __|      / _ \  | |/ /
 | _ \  \ \/\/ /  | (__      | (_) |   ' <
 |___/   \_/\_/    \___|      \___/   _|\_\

EOF

  echo " BWC is installed and ready to use."
  echo ""
  echo "Head to https://YOUR_HOST_IP/ to access the WebUI"
  echo ""
  echo "Don't forget to dive into our documentation! Here are some resources"
  echo "for you:"
  echo ""
  echo "* Documentation  - https://bwc-docs.brocade.com"
  echo "* Support        - support@brocade.com"
  echo ""
  echo "Thanks for installing Brocade Workflow Composer!"
}

trap 'fail' EXIT
# Install steps go here!
STEP="Setup args" && setup_args $@
STEP="Setup packagecloud repo" && setup_package_cloud_repo
STEP="Get package versions" && get_full_pkg_versions
STEP="Install BWC enteprise" && install_bwc_enterprise

# Install Automation Suites now
STEP="Install IP Fabric Automation Suite" && install_ipfabric_automation_suite
STEP="Setup IP Fabric Automation Suite" && setup_ipfabric_automation_suite
trap - EXIT

ok_message
