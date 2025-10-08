#!/bin/bash

# Copyright (c) 2025, WSO2 LLC. (https://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.

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
    sudo apt-get install -y ca-certificates curl > /dev/null
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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

  echo "[INFO]: Installing Java 17"
  wget -O jdk-setup.tar.gz  https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.16+8/OpenJDK17U-jdk_x64_linux_hotspot_17.0.16_8.tar.gz
  sudo rm -rf /usr/lib/jvm
  sudo mkdir /usr/lib/jvm
  sudo tar -xvf jdk-setup.tar.gz -C /usr/lib/jvm
  sudo mv /usr/lib/jvm/jdk* /usr/lib/jvm/jdk
  sudo update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/jdk/bin/java" 1
  sudo update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/jdk/bin/javac" 1
  sudo chmod a+x /usr/bin/java
  sudo chmod a+x /usr/bin/javac
  export JAVA_HOME=/usr/lib/jvm/jdk
  sudo sh -c 'echo "export JAVA_HOME=/usr/lib/jvm/jdk" >> /etc/environment'
  source /etc/environment
  echo "[INFO]: Java installation completed."
}

function download_jmeter() {

  echo "[INFO]: Downloading JMeter 5.6.3"
  JMETER_URL="https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.tgz"
  JMETER_SHA_URL="https://www.apache.org/dist/jmeter/source/apache-jmeter-5.6.3_src.tgz.sha512"
  wget -P "$HOME" "$JMETER_URL"
  wget -P "$HOME" "$JMETER_SHA_URL"
  echo "[INFO]: Verifying JMeter checksum"
  OLDPWD=$(pwd)
  cd $HOME
  sha512sum -c apache-jmeter-5.6.3.tgz.sha512
  rm -f apache-jmeter-5.6.3.tgz.sha512
  cd $OLDPWD
  if [ $? -ne 0 ]; then
    echo "[ERROR]: JMeter checksum verification failed!"
    exit 1
  fi
  echo "[INFO]: JMeter download and verification completed."
  echo "[INFO]: JMeter download completed."
}

function install_psql() {

  echo "[INFO]: Installing psql client"
  sudo apt install postgresql -y > /dev/null
  echo "[INFO]: psql client installation completed."
}

echo "[INFO]: Starting VM setup."
update_and_install_packages
install_docker
install_kubectl
install_helm
install_az_cli
install_java
download_jmeter
install_psql
echo "[INFO]: VM setup completed."
