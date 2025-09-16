#!/bin/bash

# -------------------------------------------------------------------------------------
#
# Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
#
# This software is the property of WSO2 LLC. and its suppliers, if any.
# Dissemination of any information or reproduction of any material contained
# herein in any form is strictly forbidden, unless permitted by WSO2 expressly.
# You may not alter or remove any copyright or other notice from copies of this content.
#
# --------------------------------------------------------------------------------------

USER="azureuser"
HOME="/home/$USER"


function update_and_install_packages() {

  echo "[INFO]: Updating and installing required packages."
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update  > /dev/null
  sudo apt-get upgrade -y  > /dev/null
  sudo apt-get install -y wget apt-transport-https software-properties-common > /dev/null
  echo "[INFO]: Package installation completed."
}

function install_docker() {

    echo "[INFO]: Installing Docker"
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo groupadd docker
    sudo usermod -aG docker $USER
    newgrp docker
    echo "[INFO]: Docker installation completed."
}

function install_kubectl() {

  echo "[INFO]: Installing kubectl"
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  echo "[INFO]: kubectl installation completed."
}

function install_helm() {

  echo "[INFO]: Installing Helm"
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
  echo "[INFO]: Helm installation completed."
}

function install_az_cli() {

  echo "[INFO]: Installing Azure CLI"
  curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  az aks install-cli
  echo "[INFO]: Azure CLI installation completed."
}

function install_java() {

  echo "[INFO]: Installing Java 8"
  curl -o jdk-setup.tar.gz https://s3.amazonaws.com/is-performance-test/java-setup/jdk-8u212-linux-x64.tar.gz
  sudo mkdir /usr/lib/jvm
  sudo tar -xvf jdk-setup.tar.gz -C /usr/lib/jvm
  sudo mv /usr/lib/jvm/jdk* /usr/lib/jvm/jdk
  sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/jdk/bin/java" 1
  sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/jdk/bin/javac" 1
  sudo update-alternatives --install "/usr/bin/javaws" "javaws" "/usr/lib/jvm/jdk/bin/javaws" 1
  sudo chmod a+x /usr/bin/java
  sudo chmod a+x /usr/bin/javac
  sudo chmod a+x /usr/bin/javaws
  export JAVA_HOME=/usr/lib/jvm/jdk
  sudo sh -c 'echo "export JAVA_HOME=/usr/lib/jvm/jdk" >> /etc/environment'
  source /etc/environment
  echo "[INFO]: Java installation completed."
}

function download_jmeter() {

  echo "[INFO]: Downloading JMeter 5.5"
  wget -P "$HOME" https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-3.3.tgz
  echo "[INFO]: JMeter download completed."
}

echo "[INFO]: Starting VM setup."
update_and_install_packages
install_docker
install_kubectl
install_helm
install_az_cli
install_java
download_jmeter
echo "[INFO]: VM setup completed."
