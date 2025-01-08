#!/bin/bash

# Function to create a user
create_user() {
    read -p "Enter the username to create: " USERNAME

    if id "$USERNAME" &>/dev/null; then
        echo "User $USERNAME already exists."
        read -p "Do you want to delete the existing user and recreate it? (y/n): " CHOICE
        if [[ "$CHOICE" == "y" || "$CHOICE" == "Y" ]]; then
            echo "Deleting user $USERNAME and cleaning up files..."
            
            # Stop user processes
            pkill -u "$USERNAME" 2>/dev/null
            
            # Delete user and home directory
            userdel -r "$USERNAME" && echo "User $USERNAME deleted successfully."
        else
            echo "Operation cancelled."
            exit 0
        fi
    fi

    # Create a new user
    echo "Creating user $USERNAME..."
    useradd -m -s /bin/bash "$USERNAME" || { echo "Failed to create user."; exit 1; }

    # Prompt for password
    passwd "$USERNAME"

    # Grant sudo privileges
    usermod -aG sudo "$USERNAME" && echo "User $USERNAME has been granted sudo privileges."

    # Output success message
    echo "User $USERNAME has been successfully created and configured with sudo privileges."
}

# Main script execution
create_user
