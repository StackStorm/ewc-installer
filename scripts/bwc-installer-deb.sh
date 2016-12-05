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

BWC_ENTERPRISE_VERSION=''

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
          --license=*)
          LICENSE_KEY="${i#*=}"
          shift
          ;;
          --user=*)
          USERNAME="${i#*=}"
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
  echo "         Installing BWC Entperise $RELEASE $VERSION     "
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

    local BWC_VER=$(apt-cache show bwc-enterprise | grep Version | awk '{print $2}' | grep $VERSION | sort --version-sort | tail -n 1)
    if [ -z "$BWC_VER" ]; then
      echo "Could not find requested version of bwc-enterprise!!!"
      sudo apt-cache policy bwc-enterprise
      exit 3
    fi

    BWC_ENTERPRISE_VERSION="=${BWC_VER}"
    echo "##########################################################"
    echo "#### Following versions of packages will be installed ####"
    echo "bwc-enterprise${BWC_ENTERPRISE_VERSION}"
    echo "##########################################################"
  fi
}

install_bwc_enterprise() {
  # Install BWC
  sudo apt-get update
  sudo apt-get -y install bwc-enterprise${BWC_ENTERPRISE_VERSION}
}

enable_and_configure_rbac() {
  # Enable RBAC
  sudo apt-get install -y crudini
  sudo crudini --set /etc/st2/st2.conf rbac enable 'True'

  # TODO: Move directory creation to package
  sudo mkdir -p /opt/stackstorm/rbac/assignments/
  sudo mkdir -p /opt/stackstorm/rbac/roles/

  # Write role assignment for admin user
  ROLE_ASSIGNMENT_FILE="/opt/stackstorm/rbac/assignments/${USERNAME}.yaml"
  sudo bash -c "cat > ${ROLE_ASSIGNMENT_FILE}" <<EOL
---
  username: "${USERNAME}"
  roles:
    - "system_admin"
EOL

  # Write role assignment for stanley (system) user
  ROLE_ASSIGNMENT_FILE="/opt/stackstorm/rbac/assignments/stanley.yaml"
  sudo bash -c "cat > ${ROLE_ASSIGNMENT_FILE}" <<EOL
---
  username: "stanley"
  roles:
    - "admin"
EOL

  # Sync roles and assignments
  sudo st2-apply-rbac-definitions --config-file /etc/st2/st2.conf

  # Restart st2api
  sudo st2ctl restart-component st2api
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
STEP="Install BWC enterprise" && install_bwc_enterprise
STEP="Enable and configure RBAC" && enable_and_configure_rbac
trap - EXIT

ok_message
