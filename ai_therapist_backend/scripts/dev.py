#!/usr/bin/env python3
"""
Development utility script to help with local development and Firebase deployment
"""

import os
import sys
import subprocess
import argparse
import shutil
from pathlib import Path

# Get the project root directory
ROOT_DIR = Path(__file__).parent.parent.absolute()

def run_local():
    """Run the app locally with the local environment"""
    os.environ["APP_ENV"] = "local"
    # Copy .env.local to .env if it doesn't exist
    if not os.path.exists(os.path.join(ROOT_DIR, '.env')):
        shutil.copy(os.path.join(ROOT_DIR, '.env.local'), os.path.join(ROOT_DIR, '.env'))
    
    print("Starting local development server...")
    subprocess.run(["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"], cwd=ROOT_DIR)

def deploy_to_firebase(environment="production"):
    """Deploy the app to Firebase with the specified environment"""
    if environment not in ["production", "staging", "development"]:
        print(f"Invalid environment: {environment}")
        return
    
    # Ensure we have the right .env file
    env_file = os.path.join(ROOT_DIR, f'.env.{environment}')
    if not os.path.exists(env_file):
        print(f"Environment file {env_file} not found!")
        return
    
    # Check if firebase CLI is installed
    try:
        subprocess.run(["firebase", "--version"], check=True, stdout=subprocess.PIPE)
    except (subprocess.SubprocessError, FileNotFoundError):
        print("Firebase CLI not found. Please install it with: npm install -g firebase-tools")
        return
    
    print(f"Deploying to Firebase ({environment} environment)...")
    
    # Set the APP_ENV environment variable for the deployment
    os.environ["APP_ENV"] = environment
    
    # Deploy to Firebase
    result = subprocess.run(["firebase", "deploy", "--only", "functions"], cwd=ROOT_DIR)
    
    if result.returncode == 0:
        print(f"Successfully deployed to Firebase ({environment})!")
    else:
        print("Deployment failed.")

def setup_local_env():
    """Set up the local development environment"""
    print("Setting up local development environment...")
    
    # Create .env.local if it doesn't exist
    local_env = os.path.join(ROOT_DIR, '.env.local')
    if not os.path.exists(local_env):
        with open(local_env, 'w') as f:
            f.write("""APP_ENV=local
GROQ_API_KEY=your_groq_api_key_here
OPENAI_API_KEY=your_openai_api_key_here

# Database configuration
POSTGRES_SERVER=localhost
POSTGRES_USER=postgres
POSTGRES_PASSWORD=7860
POSTGRES_DB=ai_therapist
""")
    
    # Create symbolic link from .env.local to .env
    env_file = os.path.join(ROOT_DIR, '.env')
    if os.path.exists(env_file):
        os.remove(env_file)
    shutil.copy(local_env, env_file)
    
    print("Local environment set up! Edit .env.local with your API keys.")

def main():
    parser = argparse.ArgumentParser(description='AI Therapist Backend Development Tool')
    subparsers = parser.add_subparsers(dest='command', help='Command to run')
    
    # Local development command
    local_parser = subparsers.add_parser('local', help='Run locally')
    
    # Deploy command
    deploy_parser = subparsers.add_parser('deploy', help='Deploy to Firebase')
    deploy_parser.add_argument('--env', choices=['development', 'staging', 'production'], 
                             default='production', help='Environment to deploy to')
    
    # Setup command
    setup_parser = subparsers.add_parser('setup', help='Set up development environment')
    
    args = parser.parse_args()
    
    if args.command == 'local':
        run_local()
    elif args.command == 'deploy':
        deploy_to_firebase(args.env)
    elif args.command == 'setup':
        setup_local_env()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()