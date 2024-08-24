#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if a domain was provided
if [ -z "$1" ]; then
    echo "❌ No domain provided. Usage: ./setup_ai_server.sh <your_local_domain_or_ip>"
    exit 1
fi

DOMAIN=$1

# Validate domain name format (local domains or IP)
if ! [[ $DOMAIN =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "❌ Invalid domain name provided: $DOMAIN"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check and install a package if it's not installed
check_and_install_package() {
    local package=$1
    if dpkg -l | grep -qw "$package"; then
        echo "✅ $package is already installed."
    else
        echo "⚙️ $package is not installed. Installing $package..."
        sudo apt-get install -y -qq "$package" || {
            echo "❌ Failed to install $package. Exiting."
            exit 1
        }
        echo "✅ $package installed successfully."
    fi
}

# Update and upgrade system packages securely
echo "🔄 Updating system packages... Please wait."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq || {
    echo "❌ Failed to update system packages. Please check your network connection and try again."
    exit 1
}
echo "✅ System packages updated."

# Install necessary firmware updates
echo "🔧 Updating firmware..."
sudo rpi-update -y || {
    echo "❌ Failed to update firmware. Exiting."
    exit 1
}

# Check if Docker is running
echo "🔍 Checking if Docker is running..."
if systemctl is-active --quiet docker; then
    echo "✅ Docker is running."
else
    echo "⚠️ Docker is not running. Attempting to start Docker..."
    sudo systemctl start docker || {
        echo "❌ Failed to start Docker. Exiting."
        exit 1
    }
    echo "✅ Docker started successfully."
fi

# Check and install required packages
required_packages=(apt-transport-https ca-certificates curl software-properties-common python3 python3-pip git nginx python3-certbot-nginx)
for package in "${required_packages[@]}"; do
    check_and_install_package "$package"
done

# Install Docker if not already installed
if command_exists docker; then
    echo "🐳 Docker is already installed."
else
    echo "⚙️ Docker is not installed. Installing Docker from official repositories..."
    curl -sSL https://get.docker.com | sudo sh || {
        echo "❌ Failed to install Docker. Exiting."
        exit 1
    }
    sudo usermod -aG docker $USER
    echo "✅ Docker installed successfully. Please log out and log back in or reboot to apply Docker group changes."
fi

# Install Docker Compose if not already installed
if command_exists docker-compose; then
    echo "🔗 Docker Compose is already installed."
else
    echo "⚙️ Docker Compose is not installed. Installing Docker Compose securely..."
    sudo pip3 install docker-compose || {
        echo "❌ Failed to install Docker Compose. Exiting."
        exit 1
    }
    echo "✅ Docker Compose installed successfully."
fi

# Install AI frameworks (TensorFlow Lite and PyTorch) if not already installed
echo "🐍 Checking and installing AI frameworks..."
pip_installed_packages=$(sudo pip3 list --format=columns)
if [[ $pip_installed_packages == *"tflite-runtime"* ]]; then
    echo "✅ TensorFlow Lite is already installed."
else
    echo "⚙️ TensorFlow Lite is not installed. Installing TensorFlow Lite..."
    sudo pip3 install tflite-runtime || {
        echo "❌ Failed to install TensorFlow Lite. Exiting."
        exit 1
    }
    echo "✅ TensorFlow Lite installed successfully."
fi

if [[ $pip_installed_packages == *"torch"* ]]; then
    echo "✅ PyTorch is already installed."
else
    echo "⚙️ PyTorch is not installed. Installing PyTorch..."
    sudo pip3 install torch torchvision || {
        echo "❌ Failed to install PyTorch. Exiting."
        exit 1
    }
    echo "✅ PyTorch installed successfully."
fi

# Variables
PROJECT_DIR="$HOME/ai-server"
DOCKERFILE_PATH="$PROJECT_DIR/Dockerfile"
DOCKER_COMPOSE_PATH="$PROJECT_DIR/docker-compose.yml"
APP_DIR="$PROJECT_DIR/app"
PYTHON_APP_FILE="$APP_DIR/app.py"

# Create project directory
echo "📁 Creating project directory at $PROJECT_DIR..."
sudo mkdir -p "$APP_DIR" || {
    echo "❌ Failed to create project directory. Exiting."
    exit 1
}

# Set up a simple Python web application using Flask and TensorFlow Lite
echo "🚀 Setting up the AI Python application..."
sudo cat > "$PYTHON_APP_FILE" <<EOL
from flask import Flask, request, jsonify
import tensorflow as tf
import torch
import torchvision.transforms as transforms
from PIL import Image
import io

app = Flask(__name__)

@app.route("/", methods=["GET"])
def index():
    return "Welcome to the AI Server on Raspberry Pi 4!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOL

# Create Dockerfile
echo "📝 Creating Dockerfile at $DOCKERFILE_PATH..."
sudo cat > "$DOCKERFILE_PATH" <<EOL
# Use a lightweight Python image that supports ARM architecture
FROM python:3.9-slim

# Install required packages
RUN pip install flask tflite-runtime torch torchvision

# Set the working directory
WORKDIR /app

# Copy application files to the working directory
COPY ./app /app

# Expose the necessary port
EXPOSE 8080

# Specify the default command to run your application
CMD ["python", "app.py"]
EOL

# Create docker-compose.yml
echo "📝 Creating docker-compose.yml at $DOCKER_COMPOSE_PATH..."
sudo cat > "$DOCKER_COMPOSE_PATH" <<EOL
version: '3.8'

services:
  ai-server:
    build: .
    container_name: ai-server
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./app:/app
EOL

# Build and run the AI server
echo "🚀 Building and starting the AI server..."
cd "$PROJECT_DIR"
sudo docker-compose up -d || {
    echo "❌ Failed to build and start the AI server container. Exiting."
    exit 1
}

# Check if the AI server container is running
echo "🔍 Checking if the AI server container is running..."
if [ "$(sudo docker inspect -f '{{.State.Running}}' ai-server)" = "true" ]; then
    echo "✅ AI server container is running."
else
    echo "❌ AI server container failed to start. Checking logs..."
    sudo docker logs ai-server
    exit 1
fi

# Configure Nginx for local domain (no SSL)
echo "🔐 Setting up Nginx for local domain..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo cat > /etc/nginx/sites-available/ai-server <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

sudo ln -s /etc/nginx/sites-available/ai-server /etc/nginx/sites-enabled/

# Restart Nginx to apply changes
echo "🔄 Restarting Nginx..."
sudo systemctl restart nginx || {
    echo "❌ Failed to restart Nginx. Exiting."
    exit 1
}

# Check if Nginx is running
echo "🔍 Checking if Nginx is running..."
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx is running."
else
    echo "❌ Nginx failed to start. Checking Nginx status..."
    sudo systemctl status nginx
    exit 1
fi

# Create systemd service for AI server
echo "🔧 Creating systemd service for AI server..."
sudo cat > /etc/systemd/system/ai-server.service <<EOL
[Unit]
Description=AI Server
After=docker.service
Requires=docker.service

[Service]
Restart=always
ExecStart=/usr/local/bin/docker-compose -f $DOCKER_COMPOSE_PATH up
ExecStop=/usr/local/bin/docker-compose -f $DOCKER_COMPOSE_PATH down
WorkingDirectory=$PROJECT_DIR
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOL

# Enable and start AI server service
sudo systemctl daemon-reload
sudo systemctl enable ai-server
sudo systemctl start ai-server

# Summary
echo "🎉 AI Server setup complete!"
echo "Access your AI server at: http://$DOMAIN"
