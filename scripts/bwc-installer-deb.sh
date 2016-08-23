#!/bin/bash

set -eu

VERSION=''
RELEASE='stable'
REPO_TYPE=''
REPO_PREFIX=''
USERNAME=''
PASSWORD=''
LICENSE_KEY=''

NO_LICENSE_BANNER="
LICENSE KEY not provided. You'll need a license key to install Brocade Workflow Composer (BWC).
Please visit http://www.brocade.com/en/products-services/network-automation/workflow-composer.html
to purchase or trial BWC.

Please contact sales@brocade.com if you have any questions.
"

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
  fi

  if [[ "$USERNAME" = '' || "$PASSWORD" = '' ]]; then
    echo "Let's set StackStorm admin credentials."
    echo "You can also use \"--user\" and \"--password\" for unattended installation."
    echo "Press \"ENTER\" to continue or \"CTRL+C\" to exit/abort"
    read -e -p "Admin username: " -i "st2admin" USERNAME
    read -e -s -p "Password: " PASSWORD
  fi
}

get_full_pkg_versions() {
    echo "GET PKG VERSIONS"
}

install_bwc_enterprise() {
    echo "INSTALL BWC ENTERPRISE"
}

install_ipfabric_automation_suite() {
    echo "INSTALL IPFABRIC AUTOMATION SUITES"
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
STEP="Install BWC enteprise" && install_bwc_enterprise

# Install Automation Suites now
STEP="Install IP Fabric Automation Suite" && install_ipfabric_automation_suite
trap - EXIT

ok_message
