#!/bin/bash

# Update package index
sudo apt update -y

# Install prerequisite packages
sudo apt install apt-transport-https ca-certificates curl software-properties-common -y

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the stable Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update the package index again
sudo apt update -y

# Install Docker Engine
sudo apt install docker-ce docker-ce-cli containerd.io -y

# Enable Docker to start at boot
sudo systemctl enable docker

# Start Docker service
sudo systemctl start docker

# Add current user to the docker group (optional: allows running Docker without sudo)
sudo usermod -aG docker $USER

# Install Docker Compose (latest stable version)
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep "tag_name" | cut -d '"' -f 4)
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Apply executable permissions to the Docker Compose binary
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version

echo "Docker and Docker Compose have been successfully installed."
echo "Please log out and log back in to apply the changes for user group permissions."


## curl -fsSL https://raw.githubusercontent.com/IEatLemons/Quick-Installation/main/ins-docker.sh | bash