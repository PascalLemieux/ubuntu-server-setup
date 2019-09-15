# Finds the current directory
function getCurrentDir() {
    local current_dir="${BASH_SOURCE%/*}"
    if [[ ! -d "${current_dir}" ]]; then current_dir="$PWD"; fi
    echo "${current_dir}"
}
current_dir=$(getCurrentDir)

function main() {

    # Celery user setup
    read -rp "Enter the username of the celery account:" username
    promptForPassword
    trap cleanup EXIT SIGHUP SIGINT SIGTERM
    addUserAccount "${username}" "${password}"
    disableSudoPassword "${username}"

    # Update everything
    echo "Update and Upgrade. "
    updateAndUpgrade

    # Create the directories
    echo "Creating the directories for log and pid files. "
    setupDirs

    # Create the files
    echo "Creating the log and pid files. "
    setupLogAndRunFiles

    echo "Copying celery service file. "
    copyCeleryServiceFile

    echo "Copying celery beat service file. "
    copyCeleryBeatServiceFile

    echo "Copying celery service file. "
    copyCeleryConfigurationFile

    read -rp "Enter the path to working directory (e.g. .../proj/proj/):" working_dir
    read -rp "Enter the path to project folder (e.g. .../proj/):" project_dir
    read -rp "Enter the path to the celery bin (e.g. .../proj/venv/bin/celery):" path_to_celery_bin
    read -rp "Enter the django app name (e.g. django_proj):" app_name
    read -rp "Enter the number of concurrencies (cores):" concurrencies
    read -rp "Enter the time limit for tasks (e.g. 300):" time_limit
    modifyCeleryConfigurationFile "${path_to_celery_bin}" "${app_name}" "${concurrencies}" "${time_limit}"
    modifyCeleryServiceFiles "${working_dir}"

    echo "Permissioning Django folder."
    permissionDjangoFolder "${project_dir}"

    echo "Restarting systemctl."
    sudo systemctl daemon-reload

    echo "Enabling Celery."
    sudo systemctl enable celery
    sudo systemctl restart celery

    echo "Enabling Celery Beat."
    sudo systemctl enable celerybeat
    sudo systemctl restart celerybeat

    # Cleaning up
    cleanup
    echo "Setup complete. "
}

function permissionDjangoFolder() {
    local proj_dir=$1
    sudo chmod -R a+rwx ${proj_dir}
}

function modifyCeleryServiceFiles() {

    local work_dir=$1
    work_dir_="__working_directory__"

    sudo sed -i "s/${work_dir_}/${work_dir}/g" /etc/systemd/system/celery.service
    sudo sed -i "s/${work_dir_}/${work_dir}/g" /etc/systemd/system/celerybeat.service
}


function modifyCeleryConfigurationFile() {

    local path=$1
    local app_name=$2
    local concur=$3
    local time=$4

    path_="__path_to_celery_bin__"
    app_="__celery_app_name__"
    time_="__time_limit__"
    concur_="__nb_concurrency__"

    sudo sed -i "s/${path_}/${path}/g" /etc/conf.d/celery
    sudo sed -i "s/${app_}/${app_name}/g" /etc/conf.d/celery
    sudo sed -i "s/${time_}/${time}/g" /etc/conf.d/celery
    sudo sed -i "s/${concur_}/${concur}/g" /etc/conf.d/celery
}


function updateAndUpgrade() {
    sudo apt-get --assume-yes update
    sudo apt-get --assume-yes upgrade
}

function setupDirs() {
    sudo mkdir /var/run/celery || echo "Dir already exists: /var/run/celery "
    sudo mkdir /var/log/celery || echo "Dir already exists: /var/log/celery "
    sudo mkdir /etc/conf.d || echo "Dir already exists: /etc/conf.d "
}

function setupLogAndRunFiles() {
    sudo touch /var/log/celery/w1.log  || echo "File already exists: /var/log/celery/w1.log"
    sudo touch /var/log/celery/beat.log  || echo "File already exists: /var/log/celery/beat.log"
    sudo chmod a+rw /var/log/celery/w1.log
    sudo chmod a+rw /var/log/celery/beat.log
}

function createServiceFiles() {
    # Celery
    sudo touch /etc/systemd/system/celery.service
    sudo chmod a+rw /etc/systemd/system/celery.service
    # Celery beat
    sudo touch /etc/systemd/system/celerybeat.service
    sudo chmod a+rw /etc/systemd/system/celerybeat.service
}

function createConfigurationFile() {
    sudo touch /etc/conf.d
    sudo chmod a+rw /etc/conf.d
}

function copyCeleryServiceFile() {
    #sudo rm /etc/systemd/system/celery.service || echo "No previous service file present (celery)."
    sudo cp ${current_dir}/celery.service /etc/systemd/system/celery.service
    sudo chmod a+rw /etc/systemd/system/celery.service
}

function copyCeleryBeatServiceFile() {
    #sudo rm /etc/systemd/system/celerybeat.service || echo "No previous service file present (celery beat)."
    sudo cp ${current_dir}/celerybeat.service /etc/systemd/system/celerybeat.service
    sudo chmod a+rw /etc/systemd/system/celerybeat.service
}

function copyCeleryConfigurationFile() {
    #sudo rm /etc/conf.d/celery || echo "No previous configuration file present (/conf.d)."
    sudo cp ${current_dir}/celery /etc/conf.d/celery
    sudo chmod a+rw /etc/conf.d/celery
}


# Keep prompting for the password and password confirmation
function promptForPassword() {
   PASSWORDS_MATCH=0
   while [ "${PASSWORDS_MATCH}" -eq "0" ]; do
       read -s -rp "Enter new UNIX password:" password
       printf "\n"
       read -s -rp "Retype new UNIX password:" password_confirmation
       printf "\n"

       if [[ "${password}" != "${password_confirmation}" ]]; then
           echo "Passwords do not match! Please try again."
       else
           PASSWORDS_MATCH=1
       fi
   done
}

function addUserAccount() {
    local username=${1}
    local password=${2}
    local silent_mode=${3}

    if [[ ${silent_mode} == "true" ]]; then
        sudo adduser --disabled-password --gecos '' "${username}"
    else
        sudo adduser --disabled-password "${username}"
    fi

    echo "${username}:${password}" | sudo chpasswd
    sudo usermod -aG sudo "${username}"
}

function disableSudoPassword() {
    local username="${1}"

    sudo cp /etc/sudoers /etc/sudoers.bak
    sudo bash -c "echo '${1} ALL=(ALL) NOPASSWD: ALL' | (EDITOR='tee -a' visudo)"
}

function cleanup() {
    if [[ -f "/etc/sudoers.bak" ]]; then
        revertSudoers
    fi
}

# Reverts the original /etc/sudoers file before this script is ran
function revertSudoers() {
    sudo cp /etc/sudoers.bak /etc/sudoers
    sudo rm -rf /etc/sudoers.bak
}



main