#! /bin/bash

set -ue

VERSION=''
USERNAME=''
PASSWORD=''
RELEASE='stable'
REPO_TYPE=''
LICENSE_KEY=''

BRANCH='master'

REPO_NAME='enterprise'

SUITE='dcfabric-suite'
DCFABRIC_SUITE_VERSION=''

NO_LICENSE_BANNER="
LICENSE KEY not provided. You'll need a license key to install Brocade Workflow Composer (BWC).
Please visit http://www.brocade.com/en/products-services/network-automation/workflow-composer.html
to purchase or trial BWC.

Please contact sales@brocade.com if you have any questions.
"

# XXX: Once we have our S3 buckets set up, point these to public URLs.
SETUP_SCRIPTS_BASE_PATH="https://raw.githubusercontent.com/StackStorm/bwc-installer/${BRANCH}/scripts/setup"

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

  hash curl 2>/dev/null || { echo >&2 "'curl' is not installed. Aborting."; exit 1; }

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

  if [ -z ${LICENSE_KEY} ]; then
    printf "${NO_LICENSE_BANNER}"
    exit 1
  fi

  echo "########################################################"
  echo "          Installing ${SUITE} $RELEASE $VERSION         "
  echo "########################################################"

  if [ "$REPO_TYPE" == "staging" ]; then
    printf "\n\n"
    echo "################################################################"
    echo "### Installing from staging repos!!! USE AT YOUR OWN RISK!!! ###"
    echo "################################################################"
    REPO_NAME="staging-${REPO_NAME}"
  fi

  if [ "$RELEASE" == "unstable" ]; then
    echo "########################################################"
    echo "                 Using Unstable Repos"
    echo "########################################################"
    REPO_NAME="${REPO_NAME}-unstable"
  fi


  if [[ "$USERNAME" = '' || "$PASSWORD" = '' ]]; then
    echo "This script requires Brocade Workflow Composer credentials (Username/Password) to run."
    echo "Please re-run script with --user=<USER> --password=<PASSWORD> arguments."
    exit 1
  fi
}

setup_package_cloud_repo() {
  local PKG_CLOUD_URL=https://${LICENSE_KEY}:@packagecloud.io/install/repositories/StackStorm/${REPO_NAME}/script.deb.sh
  ERROR_MSG="
    No access to enterprise repo ${PKG_CLOUD_URL}.

    LICENSE: ${LICENSE_KEY} not valid.

    Please contact support@Brocade.com. Please include the SKU and the invalid license key in the email.
  "
  curl --output /dev/null --silent --fail ${PKG_CLOUD_URL} || (printf "${ERROR_MSG}\n\n" && exit 1)
  curl -s ${PKG_CLOUD_URL} | sudo bash
}

get_full_pkg_versions() {
  if [ "$VERSION" != '' ];
  then
    local IPF_VER=$(apt-cache show ${SUITE} | grep Version | awk '{print $2}' | grep $VERSION | sort --version-sort | tail -n 1)
    if [ -z "$IPF_VER" ]; then
      echo "Could not find requested version of ${SUITE}!!!"
      sudo apt-cache policy ${SUITE}
      exit 3
    fi

    DCFABRIC_SUITE_VERSION="=${IPF_VER}"
    echo "##########################################################"
    echo "#### Following versions of packages will be installed ####"
    echo "${SUITE}${DCFABRIC_SUITE_VERSION}"
    echo "##########################################################"
  fi
}

install_network_essentials_pack() {
  sudo st2 pack install network_essentials=${DCFABRIC_SUITE_VERSION}
}

install_ipfabric_automation_suite() {
  sudo apt-get -y install ${SUITE}${DCFABRIC_SUITE_VERSION}
}

setup_ipfabric_automation_suite() {
  local IPFABRIC_SETUP_SCRIPT="${SETUP_SCRIPTS_BASE_PATH}/bwc-dcfabric-suite-setup.sh"
  local IPFABRIC_SETUP_FILE="bwc-dcfabric-suite-setup.sh"
  ERROR_MSG="
    Cannot find dcfabric setup script ${IPFABRIC_SETUP_SCRIPT}.

    Installation will abort now. Please contact support@Brocade.com with this error.
    Please include SKU and the error message in the email.
  "
  curl --output /dev/null --silent --head --fail ${IPFABRIC_SETUP_SCRIPT} || (printf "\n\n${ERROR_MSG}\n\n" && exit 1)
  echo "Downloading dcfabric setup script from: ${IPFABRIC_SETUP_SCRIPT}"
  curl -Ss -o ${IPFABRIC_SETUP_FILE} ${IPFABRIC_SETUP_SCRIPT}
  chmod +x ${IPFABRIC_SETUP_FILE}

  # echo "Running deployment script for Brocade Workflow Composer ${VERSION}..."
  echo "Generating DB password for network-essentials postgres database"
  local DB_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
  echo "OS specific script cmd: bash ${IPFABRIC_SETUP_FILE} --bwc-db-password=${DB_PASSWORD}"

  local ST2_TOKEN=$(st2 auth ${USERNAME} -p ${PASSWORD} -t)
  ST2_AUTH_TOKEN=${ST2_TOKEN} bash -c "./${IPFABRIC_SETUP_FILE} --bwc-db-password=${DB_PASSWORD}"
}

ok_message() {

cat << EOF

######   #####  #######    #    ######  ######  ###  #####     ####### #    #
#     # #     # #         # #   #     # #     #  #  #     #    #     # #   #
#     # #       #        #   #  #     # #     #  #  #          #     # #  #
#     # #       #####   #     # ######  ######   #  #          #     # ###
#     # #       #       ####### #     # #   #    #  #          #     # #  #
#     # #     # #       #     # #     # #    #   #  #     #    #     # #   #
######   #####  #       #     # ######  #     # ###  #####     ####### #    #

EOF

  echo "dcfabric-suite is installed and ready to use."
  echo "Don't forget to dive into our documentation! Here are some resources"
  echo "for you:"
  echo ""
  echo "* Documentation  - https://bwc-docs.brocade.com/solutions/dcfabric/index.html"
  echo "* Support        - support@brocade.com"
  echo ""
  echo "Thanks for installing Brocade Workflow Composer and the DC Fabric suite!"
}

trap 'fail' EXIT
# Install steps go here!
STEP="Setup args" && setup_args $@
STEP="Setup packagecloud repo" && setup_package_cloud_repo
STEP="Get package versions" && get_full_pkg_versions

# Install Automation Suites now
STEP="Install Network Essentials Pack" && install_network_essentials_pack
STEP="Install DC Fabric Automation Suite" && install_ipfabric_automation_suite
STEP="Setup DC Fabric Automation Suite" && setup_ipfabric_automation_suite
trap - EXIT

ok_message
