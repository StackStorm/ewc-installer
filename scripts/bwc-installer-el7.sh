#!/bin/bash

set -eu

VERSION=''
RELEASE='stable'
REPO_TYPE=''
LICENSE_KEY=''

NO_LICENSE_BANNER="
LICENSE KEY not provided. You'll need a license key to install Brocade Workflow Composer (BWC).
Please visit http://www.brocade.com/en/products-services/network-automation/workflow-composer.html
to purchase or trial BWC.

Please contact sales@brocade.com if you have any questions.
"

BWC_ENTERPRISE_PKG='bwc-enterprise'

REPO_NAME='enterprise'

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
          RELEASE='stable'
          shift
          ;;
          -u|--unstable)
          RELEASE='unstable'
          shift
          ;;
          --staging)
          REPO_TYPE='staging'
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

  echo "########################################################"
  echo "          Installing BWC $RELEASE $VERSION              "
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
}

setup_package_cloud_repo() {
  local PKG_CLOUD_URL=https://${LICENSE_KEY}:@packagecloud.io/install/repositories/StackStorm/${REPO_NAME}/script.rpm.sh
  ERROR_MSG="
    No access to enteprise repo ${PKG_CLOUD_URL}.

    LICENSE: ${LICENSE_KEY} not valid.

    Please contact support@Brocade.com. Please include the SKU and the invalid license key in the email.
  "
  curl --output /dev/null --silent --fail ${PKG_CLOUD_URL} || (printf "${ERROR_MSG}\n\n" && exit 1)
  curl -s ${PKG_CLOUD_URL} | sudo bash
}

get_full_pkg_versions() {
  if [ "$VERSION" != '' ];
  then

    local BWC_VER=$(repoquery --nvr --show-duplicates ${BWC_ENTERPRISE_PKG} | grep ${VERSION} | sort --version-sort | tail -n 1)
    if [ -z "$BWC_VER" ]; then
      echo "Could not find requested version of ${BWC_ENTERPRISE_PKG}!!!"
      sudo repoquery --nvr --show-duplicates ${BWC_ENTERPRISE_PKG}
      exit 3
    fi

    BWC_ENTERPRISE_PKG=${BWC_VER}
    echo "##########################################################"
    echo "#### Following versions of packages will be installed ####"
    echo "${BWC_ENTERPRISE_PKG}"
    echo "##########################################################"
  fi
}

install_bwc_enterprise() {
  sudo yum -y install ${BWC_ENTERPRISE_PKG}
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
trap - EXIT

ok_message
