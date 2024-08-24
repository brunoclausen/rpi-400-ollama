# rpi-400-ollama

#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Update and upgrade system packages
echo "🔄 Updating system packages... Please wait."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq
echo "✅ System packages updated."

# Check and install Docker
if command_exists docker; then
    echo "🐳 Docker is already installed."
else
    echo "⚙️ Docker is not installed. Installing Docker now..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    echo "✅ Docker installed successfully."
    echo "Please log out and log back in to apply Docker group changes."
    exit 0
fi

# Check and install Docker Compose
if command_exists docker-compose; then
    echo "🔗 Docker Compose is already installed."
else
    echo "⚙️ Docker Compose is not installed. Installing Docker Compose now..."
    sudo apt-get install -y -qq python3-pip
    sudo pip3 install docker-compose
    echo "✅ Docker Compose installed successfully."
fi

# Check and install Git
if command_exists git; then
    echo "📂 Git is already installed."
else
    echo "⚙️ Git is not installed. Installing Git now..."
    sudo apt-get install -y -qq git
    echo "✅ Git installed successfully."
fi

# Check and install Python
if command_exists python3; then
    echo "🐍 Python is already installed."
else
    echo "⚙️ Python is not installed. Installing Python now..."
    sudo apt-get install -y -qq python3 python3-pip
    echo "✅ Python installed successfully."
fi

# Variables
PROJECT_DIR="gpt2-webui"
DOCKERFILE_PATH="$PROJECT_DIR/Dockerfile"
DOCKER_COMPOSE_PATH="$PROJECT_DIR/docker-compose.yml"
APP_DIR="$PROJECT_DIR/app"
PYTHON_APP_FILE="$APP_DIR/app.py"

# Create project directory
echo "📁 Creating project directory at $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR"

# Create application directory
echo "📁 Creating application directory at $APP_DIR..."
mkdir -p "$APP_DIR"

# Set up a simple Python web application using Flask and GPT-2
echo "🚀 Setting up the sample Python application..."
cat > "$PYTHON_APP_FILE" <<EOL
from flask import Flask, request, jsonify
from transformers import pipeline, set_seed

app = Flask(__name__)

# Load the GPT-2 model
generator = pipeline('text-generation', model='gpt2')
set_seed(42)

@app.route("/generate", methods=["POST"])
def generate_text():
    data = request.json
    prompt = data.get("prompt", "")
    max_length = data.get("max_length", 50)
    results = generator(prompt, max_length=max_length, num_return_sequences=1)
    return jsonify(results)

@app.route("/", methods=["GET"])
def index():
    return "Welcome to the GPT-2 WebUI!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOL

# Create Dockerfile
echo "📝 Creating Dockerfile at $DOCKERFILE_PATH..."
cat > "$DOCKERFILE_PATH" <<EOL
# Use a lightweight Python image that supports ARM architecture
FROM python:3.9-slim

# Install required packages
RUN pip install flask transformers

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
cat > "$DOCKER_COMPOSE_PATH" <<EOL
version: '3.8'

services:
  gpt2-webui:
    build: .
    container_name: gpt2-webui
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./app:/app
EOL

# Summary
echo "🎉 Setup complete!"
echo "To start the services, navigate to the project directory and run the following commands:"
echo "  cd $PROJECT_DIR"
echo "  docker-compose up -d"
echo "After running these commands, your GPT-2 web interface will be accessible at http://localhost:8080"
