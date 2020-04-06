#!/bin/bash

set -eu

VERSION=''
RELEASE='stable'
REPO_TYPE=''
LICENSE_KEY=''

NO_LICENSE_BANNER="
LICENSE KEY not provided. You'll need a license key to install Extreme Workflow Composer (EWC).
Please visit https://www.extremenetworks.com/product/workflow-composer/
to purchase or trial EWC.

For obtaining a subscription license, please contact us at ewc-team@extremenetworks.com
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
          --user=*)
          USERNAME="${i#*=}"
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
  echo "        Installing EWC Enterprise $RELEASE $VERSION     "
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

  # NOTE: st2-rbac-backend package has been introduced in v3.0.0(dev) so we only try to install
  # it if version >= 3.0.0[dev]
  if [[ "$VERSION" =~ ^[3-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$VERSION" =~ ^[3-9]+\.[0-9]+dev$ ]]; then
    IS_V300_OR_ABOVE="true"
  else
    IS_V300_OR_ABOVE="false"
  fi
}

setup_package_cloud_repo() {
  local PKG_CLOUD_URL=https://${LICENSE_KEY}:@packagecloud.io/install/repositories/StackStorm/${REPO_NAME}/script.rpm.sh
  ERROR_MSG="
    No access to enterprise repo ${PKG_CLOUD_URL}.

    LICENSE: ${LICENSE_KEY} not valid.

    Please contact support@extremenetworks.com. Please include the SKU and the invalid license key in the email.
  "
  curl --output /dev/null --silent --fail ${PKG_CLOUD_URL} || (printf "${ERROR_MSG}\n\n" && exit 1)
  curl -s ${PKG_CLOUD_URL} | sudo bash
}

get_full_pkg_versions() {
  if [ "$VERSION" != '' ];
  then

    local BWC_VER=$(repoquery -y --nvr --show-duplicates ${BWC_ENTERPRISE_PKG} | grep -F bwc-enterprise-${VERSION} | sort --version-sort | tail -n 1)
    if [ -z "$BWC_VER" ]; then
      echo "Could not find requested version of ${BWC_ENTERPRISE_PKG}!!!"
      sudo repoquery -y --nvr --show-duplicates ${BWC_ENTERPRISE_PKG}
      exit 3
    fi

    local ST2FLOW_VER=$(repoquery -y --nvr --show-duplicates st2flow | grep -F st2flow-${VERSION} | sort --version-sort | tail -n 1)
    if [ -z "$ST2FLOW_VER" ]; then
      echo "Could not find requested version of st2flow!!!"
      sudo repoquery -y --nvr --show-duplicates st2flow
      exit 3
    fi

    local ST2LDAP_VER=$(repoquery -y --nvr --show-duplicates st2-auth-ldap | grep -F st2-auth-ldap-${VERSION} | sort --version-sort | tail -n 1)
    if [ -z "$ST2LDAP_VER" ]; then
      echo "Could not find requested version of st2-auth-ldap!!!"
      sudo repoquery -y --nvr --show-duplicates st2-auth-ldap
      exit 3
    fi

    # NOTE: This package has been introduced in v3.0.0(dev) version
    if [ "${IS_V300_OR_ABOVE}" = "true" ]; then
      local ST2_RBAC_BACKEND_VER=$(repoquery -y --nvr --show-duplicates st2-rbac-backend | grep -F st2-rbac-backend-${VERSION} | sort --version-sort | tail -n 1)
      if [ -z "$ST2_RBAC_BACKEND_VER" ]; then
        echo "Could not find requested version of st2-rbac-backend!!!"
        sudo repoquery -y --nvr --show-duplicates st2-rbac-backend
        exit 3
      fi
    fi

    local BWCUI_VER=$(repoquery -y --nvr --show-duplicates bwc-ui | grep -F bwc-ui-${VERSION} | sort --version-sort | tail -n 1)
    if [ -z "$BWCUI_VER" ]; then
      echo "Could not find requested version of bwc-ui!!!"
      sudo repoquery -y --nvr --show-duplicates bwc-ui
      exit 3
    fi

    if [ "${IS_V300_OR_ABOVE}" = "true" ]; then
      BWC_ENTERPRISE_PKG="${BWC_VER} ${ST2FLOW_VER} ${ST2LDAP_VER} ${ST2_RBAC_BACKEND_VER} ${BWCUI_VER}"
    else
      BWC_ENTERPRISE_PKG="${BWC_VER} ${ST2FLOW_VER} ${ST2LDAP_VER} ${BWCUI_VER}"
    fi

    echo "##########################################################"
    echo "#### Following versions of packages will be installed ####"
    echo "${BWC_ENTERPRISE_PKG}"
    echo "##########################################################"
  fi
}

install_enterprise() {
  # Install EWC
  sudo yum -y install ${BWC_ENTERPRISE_PKG}
}

enable_and_configure_rbac() {
  # Enable RBAC
  sudo yum -y install crudini
  sudo crudini --set /etc/st2/st2.conf rbac enable 'True'
  sudo crudini --set /etc/st2/st2.conf rbac backend 'enterprise'

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
     (  (       (         ( /(   ( /(
 (   )\))(   '  )\        )\())  )\())
 )\ ((_)()\ ) (((_)      ((_)\| ((_)\
((_)_(())\_)())\___        ((_)  _((_)
| __\ \((_)/ ((/ __|      / _ \  |/ /
| _| \ \/\/ / | (__      | (_) | ' <
|___| \_/\_/   \___|      \___/_ |\_\

EOF

  echo " EWC is installed and ready to use."
  echo ""
  echo "Head to https://YOUR_HOST_IP/ to access the WebUI"
  echo ""
  echo "Don't forget to dive into our documentation! Here are some resources"
  echo "for you:"
  echo ""
  echo "* Documentation  - https://ewc-docs.extremenetworks.com"
  echo "* Support        - support@extremenetworks.com"
  echo ""
  echo "Thanks for installing Extreme Workflow Composer!"
}

trap 'fail' EXIT
# Install steps go here!
STEP="Setup args" && setup_args $@
STEP="Setup packagecloud repo" && setup_package_cloud_repo
STEP="Get package versions" && get_full_pkg_versions
STEP="Install Enterprise" && install_enterprise
STEP="Enable and configure RBAC" && enable_and_configure_rbac
trap - EXIT

ok_message
