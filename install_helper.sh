#!/usr/bin/env bash
#
# This script:
# 1. Asks the user for a GitHub repository URL.
# 2. Clones the repository locally.
# 3. Locates the README file in the cloned repo.
# 4. Sends the README contents to GPT-4o (via the OpenAI API), requesting a Bash install script.
# 5. Saves and executes the returned install script.
# 6. Prompts the user for a language choice.
# 7. Sends the README to GPT-4o again, requesting simplified instructions in HTML in the chosen language.
# 8. Saves those instructions in an HTML file and opens them.
#
# Requirements:
# - git (to clone repos)
# - jq (to parse/manipulate JSON)
# - An environment variable named OPENAI_API_KEY must be set with your API key
#
# Usage:
#   1) Make this file executable:  chmod +x script_name.sh
#   2) Run it: ./script_name.sh
#
# Example:
#   OPENAI_API_KEY="sk-123456..." ./script_name.sh
#

#########################################
# Check for OPENAI_API_KEY in env       #
#########################################
if [ -z "$OPENAI_API_KEY" ]; then
  echo "Error: No OpenAI API key found in environment variable OPENAI_API_KEY."
  echo "Please export your key, for example: export OPENAI_API_KEY='sk-...'"
  exit 1
fi

#######################################
# 1. Prompt user for GitHub repo URL  #
#######################################
echo "Welcome! This script will clone a GitHub repository, generate and run an install script, and then provide simplified instructions in your desired language."
read -p "Please enter the GitHub repository URL (e.g., https://github.com/owner/repo.git): " REPO_URL

if [[ -z "$REPO_URL" ]]; then
  echo "No URL provided. Exiting."
  exit 1
fi

###################################
# 2. Clone the repository locally #
###################################
echo "Cloning the repository from: $REPO_URL"
git clone "$REPO_URL"

# Extract repository name from the URL
REPO_NAME=$(basename "$REPO_URL" .git)

# Check if the repository directory was created
if [ ! -d "$REPO_NAME" ]; then
  echo "Error: Repository directory '$REPO_NAME' not found. Clone may have failed."
  exit 1
fi

############################################
# 3. Locate the README file in the project #
############################################
# We try some common README filenames. If not found, attempt a 'find' as a fallback.
README_PATH=""
if [ -f "$REPO_NAME/README.md" ]; then
  README_PATH="$REPO_NAME/README.md"
elif [ -f "$REPO_NAME/README" ]; then
  README_PATH="$REPO_NAME/README"
else
  # Attempt to locate any file named like 'readme*' (case-insensitive)
  README_PATH=$(find "$REPO_NAME" -iname "readme*" | head -n 1)
fi

if [ -z "$README_PATH" ]; then
  echo "No README file found in the repository. Exiting."
  exit 1
fi

echo "Found README file at: $README_PATH"

####################################
# 4. Send the README to GPT-4o API #
####################################
# Read the entire README content into a variable.
README_CONTENT="$(cat "$README_PATH")"

# We'll escape the README content properly using 'jq' so that multi-line strings,
# quotes, etc. do not break JSON parsing.
SYSTEM_PROMPT="You are a helpful AI assistant. You will be provided with a README file content, from which you must produce a single bash script that will install the package indicated in the README if possible."
USER_PROMPT="Please create a bash script to install the package described in the README. Make sure the script is self-contained and contains steps to install all dependencies if possible. Reply with the script only and nothing else. No label, no triplebackticks."

echo "Requesting an installation Bash script from GPT-4o. Please wait..."

# Construct the JSON payload safely via jq
REQUEST_PAYLOAD="$(jq -n \
  --arg model "gpt-4o" \
  --arg system_prompt "$SYSTEM_PROMPT" \
  --arg readme "$README_CONTENT" \
  --arg user_prompt "$USER_PROMPT" \
  '{
    model: $model,
    messages: [
      {
        "role": "system",
        "content": $system_prompt
      },
      {
        "role": "user",
        "content": ("README content:\n" + $readme + "\n\n" + $user_prompt)
      }
    ]
  }'
)"

INSTALL_SCRIPT_RESPONSE="$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$REQUEST_PAYLOAD")"

# Extract the content from the JSON response
INSTALL_SCRIPT="$(echo "$INSTALL_SCRIPT_RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)"

if [ -z "$INSTALL_SCRIPT" ] || [ "$INSTALL_SCRIPT" == "null" ]; then
  echo "No install script was returned from GPT-4o or an error occurred. Exiting."
  echo "Full response from GPT-4o was:"
  echo "$INSTALL_SCRIPT_RESPONSE"
  exit 1
fi

###############################
# 5. Save and run the script  #
###############################
INSTALL_SCRIPT_FILE="install_script.sh"
echo "Saving the install script to $INSTALL_SCRIPT_FILE..."
echo "$INSTALL_SCRIPT" > "$INSTALL_SCRIPT_FILE"
chmod +x "$INSTALL_SCRIPT_FILE"

echo "Running the install script now..."
./"$INSTALL_SCRIPT_FILE"

#####################################################################
# 6. Ask the user in which language they want the simplified docs   #
#####################################################################
echo "In which language would you like the simplified instructions?"
read -p "Language (e.g. 'English', 'Spanish', 'French', 'German', etc.): " USER_LANGUAGE

if [[ -z "$USER_LANGUAGE" ]]; then
  echo "No language entered. Exiting."
  exit 1
fi

############################################################################################################
# 7. Request from GPT-4o a simplified instruction set in the requested language from the README as HTML     #
############################################################################################################
echo "Requesting simplified instructions from GPT-4o in $USER_LANGUAGE as HTML. Please wait..."

SYSTEM_PROMPT_2="You are a helpful AI assistant. You will be provided with a README file content, from which you must produce a simplified set of instructions in the user requested language, returning the response as HTML."
USER_PROMPT_2="README content:\n(See below)\n\nLanguage requested: $USER_LANGUAGE\n\nPlease create a simplified set of instructions in the requested language, focusing on the essential steps. Return the instructions as valid HTML. Only provide the HTML content."

SECOND_REQUEST_PAYLOAD="$(jq -n \
  --arg model "gpt-4o" \
  --arg system_prompt "$SYSTEM_PROMPT_2" \
  --arg readme "$README_CONTENT" \
  --arg language "$USER_LANGUAGE" \
  '{
    model: $model,
    messages: [
      {
        "role": "system",
        "content": $system_prompt
      },
      {
        "role": "user",
        "content": ("README content:\n" + $readme + "\n\nLanguage requested: " + $language + "\n\nPlease create a simplified set of instructions in the requested language, focusing on the essential steps. Return the instructions as valid HTML. Only provide the HTML content.")
      }
    ]
  }'
)"

INSTRUCTIONS_RESPONSE="$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "$SECOND_REQUEST_PAYLOAD")"

SIMPLIFIED_INSTRUCTIONS_HTML="$(echo "$INSTRUCTIONS_RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)"

if [ -z "$SIMPLIFIED_INSTRUCTIONS_HTML" ] || [ "$SIMPLIFIED_INSTRUCTIONS_HTML" == "null" ]; then
  echo "No simplified instructions were returned from GPT-4o or an error occurred."
  echo "Full response from GPT-4o was:"
  echo "$INSTRUCTIONS_RESPONSE"
  exit 1
fi

###################################################################################################
# 8. Save the simplified instructions as an HTML file and open them in the default browser (macOS) #
###################################################################################################
HTML_FILE="simplified_instructions.html"
echo "Saving simplified instructions to $HTML_FILE..."
echo "$SIMPLIFIED_INSTRUCTIONS_HTML" > "$HTML_FILE"

# Attempt to open the file. On macOS, 'open' is typically used.
# On Linux, you might prefer 'xdg-open'. Adjust as needed.
echo "Opening $HTML_FILE..."
open "$HTML_FILE" 2>/dev/null || echo "Could not open file automatically. Please open $HTML_FILE manually."

echo ""
echo "All done! Thank you for using this script."
