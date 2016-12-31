#!/usr/bin/env bash

# ########################################################################### #
#
# Generate a GPG keyring with a given key, useful in automation
#
# ########################################################################### #

TMP_PROGRAM_VERSION="0.2";

# ............................................................................ #
# Prerequisites:
# - gnu utils (apt-get install coreutils)
# - find (apt-get install findutils)
# - sed (apt-get install sed)
# - gpg, GPG key creator (apt-get install gnupg)
# - haveged, entropy generator (apt-get install haveged)


# ............................................................................ #
# turn on tracing of error, this will bubble up all the error codes
# basically this allows the ERR trap is inherited by shell functions
set -o errtrace;
# turn on quiting on first error
set -o errexit;
# error out on undefined variables
set -o nounset;
# propagate pipe errors
set -o pipefail;
# debugging
#set -o xtrace;


# ............................................................................ #
# get script name
TMP_SCRIPT_NAME=$(basename "${0}");
# get full path of the script folder
TMP_SCRIPT_FOLDER="$(cd $(dirname $0); pwd)";
# artly plugin display name, extracted from environment otherwise set to ""
ARTLY_PLUGIN=${ARTLY_PLUGIN:-""}
# aptly script path
ARTLY_SCRIPT_PATH="${ARTLY_SCRIPT_PATH:-}";


# ............................................................................ #
# variables to store script arguments in
# static defaults are set here
# dynamic ones, which are based on other passed in parameters are set in
# process_script_arguments
# TODO: figure out a better way, prolly use -z
TMP_OPTION_OUTPUT_FOLDER="";
TMP_KEY_FILE="";
TMP_OPTION_GPG="";
TMP_OPTION_RECREATE=0;
TMP_OPTION_MACHINE_READABLE=0;
TMP_OPTION_WORK_FOLDER="";

TMP_OPTION_VERBOSE=0;
TMP_OPTION_QUIET=0;
TMP_OPTION_NO_COLOR=0;
TMP_OPTION_DEBUG=0;
TMP_OPTION_VERSION=0;

# verbosity
TMP_GPG_VERBOSITY="";
TMP_RM_VERBOSITY="";
TMP_MKDIR_VERBOSITY="";
TMP_CP_VERBOSITY="";
TMP_CHMOD_VERBOSITY="";

# initialize homedir, gpg cong and gpg key script variable
# they will be updated by process_script_arguments
# also gpg error log to handle gpg stderr oddities
TMP_WORK_FOLDER_NAME_TEMPLATE="/tmp/artly-make-keyring.XXXXXXXXXX";
TMP_GPG_ERROR_LOG="";
TMP_GPG_HOMEDIR_FOLDER="";
TMP_GPG_CONF_FILE="";

# keyrings file paths
TMP_KEYRING_FILE="";
TMP_SECRET_KEYRING_FILE="";
TMP_KEYID="";
TMP_SHRED_VERBOSITY="";

# flag to track if we created the output folder, necessary because of the
# error trapping removing the folder when we did not create it
# default to 0 so this way we do not remove the folder
TMP_CREATED_OUTPUT_FOLDER=0;


# ............................................................................ #
# print script usage
function usage {

    local script_display_name;

    if [ "${ARTLY_PLUGIN}" == "" ]; then
        script_display_name="${TMP_SCRIPT_NAME}";
    else
        script_display_name="${ARTLY_PLUGIN}";
    fi

    echo "\
${script_display_name} - generate GPG keyrings from given keys

Usage: ${script_display_name} [OPTIONS]

Generate GPG keyrings, import the given key into them and place them output
folder.

Options:

    -o, --output-folder <path>
        Output folder for generated keyring.

    -k, --key-file <path>
        Key file to import into keyring.

    --gpg <gpg path>
        Optional, use the gpg executable specified by <gpg path>. By default
        set to the first gpg executble found on the PATH using \"type -P gpg\"
        command.

    --recreate
        Optional, delete previous output folder by the same name before
        creating it again. Useful when you want to recreate the keys without
        having to fo manual removal.

    --machine-readable
        Optional, print out colon separated output. This only prints out the
        keyring information.

    --work-folder <path>
        Optional, work folder path, needed to generate the keyrings. By default
        the work folder name is created by mktemp using following template
        \"${TMP_WORK_FOLDER_NAME_TEMPLATE}\".

    -v, --verbose
        Optional, turn on verbose output.

    -q, --quiet
        Optional, be as quiet as possible. This really only print the very
        final output and not any \"work in progress\" messages.

    --no-color
        Optional, do not colorize output.

    --debug
        Optional, turn on debug. Currently this means that the work folder is
        not deleted after the script is done so it can be used for inspection.
        Also turn on --verbose/-b option.

    --version
        Print version.

    -h, --help
        show help for this script.

Notes:

    no-random-seed-file set in gpg.conf used during key generation.
";

}



# ........................................................................... #
# ERR EXIT INT TERM signals trap handler which clears the ERR trap, prints out
# script, status code line number of the error then exit
# :{1}: line on which error occured
# :{2}: status code of the errors
# :{3}: signal code of the error
# :globals: ERR EXIT INT TERM
# :error: any errors that occure when trap for ERR EXIT INT TERM is removed
# :trap ERR: clears ERR trap
# :return 0: on success, when no errors occured
# :exit 1: anything code propagated when trap for ERR EXIT INT TERM is removed
function trap_handler {
    # get error line and error description
    local error_line="${1}";
    local exit_code="${2}";
    local error_signal="${3}";

    local frame=0;
    local frame_expression;
    local indent="";

    # clear all traps so we do not hit recusions
    clear_error_traps;

    if [ "${error_signal}" == "ERR" ]; then
        # print out error code
        echo "!! Error in script : $(caller | cut -d' ' -f2)" >&2;
        echo "!! Error exit code : ${exit_code}" >&2;
        echo "!! Error line      : ${error_line}" >&2;
        echo "!! Error signal    : ${error_signal}" >&2;

        echo "----- begin stack trace ----";
        # turn off errtrace and errexit so we can can stop iterating over frames
        # when caller does not return 0 error code
        set +o errtrace;
        set +o errexit;
        while frame_expression=$(caller $frame); do
            echo "${indent}${frame_expression}";
            indent="${indent} ";
            ((frame++));
        done
        # turn exit flags back on
        set -o errtrace;
        set -o errexit;
        echo "----- end stack trace   ----";

        echo "Unexpected script error, deleting output and work folders as \
needed.">&2;
        remove_temporary_directories_and_files;
        exit 1;
    elif [ "${error_signal}" == "TERM" ]; then
        echo "Unexpected script termination, deleting output and work folders \
as needed.">&2;
        remove_temporary_directories_and_files;
        exit 1;
    elif [ "${error_signal}" == "INT" ]; then
        echo "Unexpected script interruption, deleting output and work \
folders as needed.">&2;
        remove_temporary_directories_and_files;
    elif [ "${error_signal}" == "EXIT" ]; then
        if [ ${exit_code} -ne 0 ]; then
            echo "Unexpected script exit, deleting output and work \
folders as needed.">&2;
            remove_temporary_directories_and_files;
        fi
    fi
}


# ............................................................................ #
# clear all (ERR EXIT INT TERM) error traps
function clear_error_traps {
    # clear all traps so we do not hit recusions
    trap - ERR EXIT INT TERM;
}


# ............................................................................ #
# check commands, parse scripts, and run the install/setup steps
function begin () {

    # handle script errors by trapping ERRR
    trap 'trap_handler ${LINENO} $? ERR' ERR;
    trap 'trap_handler ${LINENO} $? EXIT' EXIT;
    trap 'trap_handler ${LINENO} $? INT' INT;
    trap 'trap_handler ${LINENO} $? TERM' TERM;

    # check for commands we use and error out if they are not found
    check_commands;

    # process script arguments
    process_script_arguments "$@";

    # run script arguments (--version for example)
    maybe_run_script_arguments;

    # validate script arguments and set default
    validate_and_default_arguments;

    # enable color, if they are supported
    if [ $TMP_OPTION_NO_COLOR == 1 ]; then
        disable_color_vars;
    else
        maybe_enable_color_vars;
    fi

    # log script paths and various information
    log_script_info;

    # create folders
    create_folders;

    # create gpg config file
    create_gpg_config_file;

    # import the gpg key
    import_gpg_key;

    # detect keyrings, set TMP_KEYRING_FILE and TMP_SECRET_KEYRING_FILE to them
    TMP_KEYRING_FILE="$(get_keyring_file_path 'public')";
    TMP_SECRET_KEYRING_FILE="$(get_keyring_file_path 'secret')";

    # copy the keyring files
    copy_keyrings;

    # if not debugging remove the work folder
    if [ ${TMP_OPTION_DEBUG} -eq 0 ]; then
        remove_work_folder;
    fi

    # print keyrings
    print_keyring_information;

}


# ............................................................................ #
# checks for all the commands required for setup and activate
# this does not include the python commands we install
function check_commands {

    # check for bash 4
    cmd_exists_bash4_or_abort;

    # check gnu getop
    cmd_exists_gnu_getopt_or_abort;

    # check for a whole set of commands
    cmds_exists_or_abort \
        "echo" "basename" "dirname" "mkdir" "rm" "rev" "cp" "find" "shred";

}


# ............................................................................ #
# log paths and various scripts information
function log_script_info {

    log_verbose "Output folder : ${TMP_OPTION_OUTPUT_FOLDER}";
    log_verbose "Key file      : ${TMP_KEY_FILE}";
    log_verbose "Recreate      : $(humanize_bool ${TMP_OPTION_RECREATE})";
    log_verbose "GPG executable: ${TMP_OPTION_GPG}";
    log_verbose "GPG version   : $(gpg_version ${TMP_OPTION_GPG})";
    log_verbose "Work folder   : ${TMP_OPTION_WORK_FOLDER}";
    log_verbose "GPG homedir   : ${TMP_GPG_HOMEDIR_FOLDER}";
    log_verbose "gpg.conf      : ${TMP_GPG_CONF_FILE}";
    log_verbose "Debug         : $(humanize_bool ${TMP_OPTION_DEBUG})";

}


# ............................................................................ #
# get script params and store them
function process_script_arguments {

    local short_args;
    local long_args="";
    local processed_args;

    short_args="o: k: v q h";
    long_args+="output-folder: key-file: gpg: recreate machine-readable ";
    long_args+="work-folder: verbose quiet no-color debug version help";

    # if no arguments given print usage
    if [ $# -eq 0 ]; then
        clear_error_traps;
        usage 1>&2;
        echo "No arguments given">&2;
        exit 2;
    fi

    # process the arguments, if failed then print out all unknown arguments
    # and exit with code 2
    processed_args=$(get_getopt "${short_args}" "${long_args}" "$@") \
    || {
        clear_error_traps;
        echo "Unknown argument(s) given: ${processed_args}"; \
        exit 2;
       }

    # set the processed arguments into the $@
    eval set -- "${processed_args}";

    # go over the arguments
    while [ $# -gt 0 ]; do
        case "$1" in

            # store output folder path
            --output-folder | -o)
                TMP_OPTION_OUTPUT_FOLDER="${2}";
                shift;
                ;;

            # store output folder path
            --key-file | -k)
                TMP_KEY_FILE="${2}";
                shift;
                ;;

            # store gpg executable path
            --gpg)
                TMP_OPTION_GPG="${2}";
                shift;
                ;;

            # store machine readable flag
            --machine-readable)
                TMP_OPTION_MACHINE_READABLE=1;
                ;;

            # store recreate flag
            --recreate)
                TMP_OPTION_RECREATE=1;
                ;;

            # store work folder path
            --work-folder | -w)
                TMP_OPTION_WORK_FOLDER="${2}";
                shift
                ;;

            # store verbose flag
            --verbose | -v)
                TMP_OPTION_VERBOSE=1;
                ;;

            # store quiet flag
            --quiet | -q)
                TMP_OPTION_QUIET=1;
                ;;

            # store no color flag
            --no-color)
                TMP_OPTION_NO_COLOR=1;
                ;;

            # store debug flag
            --debug)
                TMP_OPTION_DEBUG=1;
                ;;

            # store version flag
            --version)
                TMP_OPTION_VERSION=1;
                ;;

            # show usage and quit with code 0
            --help | -h)
                usage;
                exit 0;
                ;;

            # argument end marker
            --)
                # pop the marker of the stack
                shift;
                # there should not be any trailing arguments
                if [ "${#}" -gt 0 ]; then
                    # print usage to stderr exit with code 2
                    clear_error_traps;
                    usage 1>&2;
                    echo "Unknown arguments(s) given: ${@}">&2;
                    exit 2;
                else
                    # if it 0 then break the loop, so the shift at the end
                    # of the for loop did not cause an error
                    break;
                fi
                ;;

            # unknown argument: anything that starts with -
            -*)
                # print usage to stderr exit with code 2
                clear_error_traps;
                usage 1>&2;
                echo "Unknown argument(s) given.">&2;
                exit 2;
                ;;

            *)
                # print usage to stderr since no valid command was provided
                clear_error_traps;
                usage 1>&2;
                echo "No arguments given.">&2;
                exit 2;
                ;;
        esac;
        shift;
    done

}


# ............................................................................ #
# run functionality specific only to some arguments.
# these are independent arguments not specific to rest of scrip functionality
# (for example, --version)
function maybe_run_script_arguments {

    # check if asked to print version
    if [ "${TMP_OPTION_VERSION}" -eq 1 ]; then
        print_version;
        exit;
    fi

}


# ............................................................................ #
# print out version
function print_version {

    local artly_arguments;

    if [ "${TMP_OPTION_MACHINE_READABLE}" -eq 1 ]; then
        echo "artly-make-keyring-version:${TMP_PROGRAM_VERSION}";
        artly_arguments="--machine-readable";
    else
        echo "Artly Make Keyring version: ${TMP_PROGRAM_VERSION}";
        artly_arguments="";
    fi

    # print out artly version if the script was run as an Artly plugin
    if [ "${ARTLY_SCRIPT_PATH}" != "" ]; then
        "${ARTLY_SCRIPT_PATH}" \
            ${artly_arguments} \
            --version;
    fi

}


# ........................................................................... #
# validate the set script arguments and set all default values that are
# not set at the top of the script when variable containing them are declared
function validate_and_default_arguments {

    # full path for the imported key
    if [ "${TMP_KEY_FILE}" == "" ]; then
        abort "Please specify key file using --key-file/-k" 1;
    fi

    # output folder for the keyrings
    if [ "${TMP_OPTION_OUTPUT_FOLDER}" == "" ]; then
        abort "Please specify output folder using --output-folder/-o" 1;
    fi

    # create a default work folder using a mktemp and
    # TMP_WORK_FOLDER_NAME_TEMPLATE template
    if [ "${TMP_OPTION_WORK_FOLDER}" == "" ]; then
        TMP_OPTION_WORK_FOLDER="$(\
          mktemp \
            --directory \
            --dry-run \
            ${TMP_WORK_FOLDER_NAME_TEMPLATE}
        )";
    fi

    # default virtualenv to gpg executable
    if [ "${TMP_OPTION_GPG}" == "" ]; then
        TMP_OPTION_GPG="$(type -P gpg)";
    fi
    # check if gpg we have found exists
    cmds_exists_or_abort "${TMP_OPTION_GPG}";

    # if debug then turn on verbosity
    if [ ${TMP_OPTION_DEBUG} -eq 1 ]; then
        TMP_OPTION_VERBOSE=1;
    fi

    # if verbose the set gpg, rm, mkdir verbosity
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        TMP_GPG_VERBOSITY="--verbose";
        TMP_RM_VERBOSITY="--verbose";
        TMP_MKDIR_VERBOSITY="--verbose";
        TMP_CP_VERBOSITY="--verbose"
        TMP_CHMOD_VERBOSITY="--verbose";
        TMP_SHRED_VERBOSITY="--verbose";
    else
        TMP_GPG_VERBOSITY="";
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
        TMP_CP_VERBOSITY="";
        TMP_CHMOD_VERBOSITY="";
        TMP_SHRED_VERBOSITY="";
    fi

    # if quiet, set verbosity to 0 and enforce the quietest options for
    # those utilities that have it (gpg, chmod)
    if [ ${TMP_OPTION_QUIET} -eq 1 ]; then
        TMP_OPTION_VERBOSE=0;

        TMP_GPG_VERBOSITY="--quiet";
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
        TMP_CP_VERBOSITY="";
        TMP_CHMOD_VERBOSITY="--quiet";
        TMP_SHRED_VERBOSITY="";
    fi

    # gpg error log, only available after work folder has been created
    TMP_GPG_ERROR_LOG="${TMP_OPTION_WORK_FOLDER}/gpg_error.log"
    # home dir use to "sandbox" execution of gpg
    TMP_GPG_HOMEDIR_FOLDER="${TMP_OPTION_WORK_FOLDER}/gpg_homedir";
    # gpg.conf options file
    TMP_GPG_CONF_FILE="${TMP_GPG_HOMEDIR_FOLDER}/gpg.conf";

}


# ........................................................................... #
# remove all the temporary folders and files if debug is that
# this removes output and work folder
function remove_temporary_directories_and_files {

    # if debug is NOT set "force" remove output and work folder
    # BUT!!! only remove the output folder if we created it. this helps not to
    # remove it when we remove is attempted from error handling
    if [ ${TMP_OPTION_DEBUG} -eq 0 ]; then
        if [ ${TMP_CREATED_OUTPUT_FOLDER} -eq 1 ]; then
            # remove the work for this script folder if exist
            if [ -d "${TMP_OPTION_OUTPUT_FOLDER}" ]; then
                rm \
                    ${TMP_RM_VERBOSITY} \
                    --recursive \
                    "${TMP_OPTION_OUTPUT_FOLDER}";
                log_unquiet "Removed output folder: \
${TMP_OPTION_OUTPUT_FOLDER}";
            fi
        else
            log_unquiet "Did not remove the output folder, \
since we did not create it.";
        fi

        # always remove work folder
        remove_work_folder;
    fi

}


# ........................................................................... #
# create output, work, homedir folder removing them if needed
# also homedir folder permissions are set at 700
function create_folders {

    # create output folder
    create_output_folder

    # remove work folder if exists
    remove_work_folder;
    # create work folder
    mkdir \
        ${TMP_MKDIR_VERBOSITY} \
        --parent \
        "${TMP_OPTION_WORK_FOLDER}";
    log_unquiet "Created work folder: ${TMP_OPTION_WORK_FOLDER}";

    # create gpg homedir folder & set it's permission to 700 as required by gpg
    mkdir \
        ${TMP_MKDIR_VERBOSITY} \
        --parent \
        "${TMP_GPG_HOMEDIR_FOLDER}";
    # set folder permission to 700 as gpg requires
    chmod \
        ${TMP_CHMOD_VERBOSITY} \
        700 \
        "${TMP_GPG_HOMEDIR_FOLDER}";
}


# ........................................................................... #
# create output folder, remove it if already exists and recreate is true
# otherwise abort suggesting recreate option
function create_output_folder {

    if [ -d "${TMP_OPTION_OUTPUT_FOLDER}" ]; then

        if [ ${TMP_OPTION_RECREATE} -eq 1 ]; then

            # shred all the files in the output folder, cause private keys
            shred_recursively \
                "${TMP_SHRED_VERBOSITY}" \
                "${TMP_OPTION_OUTPUT_FOLDER}";

            # remove the output folder
            rm \
                ${TMP_RM_VERBOSITY} \
                --recursive \
                "${TMP_OPTION_OUTPUT_FOLDER}";
            log_unquiet "Shredded and removed output folder: \
${TMP_OPTION_OUTPUT_FOLDER}";

            # create output folder
            mkdir \
                ${TMP_MKDIR_VERBOSITY} \
                --parent \
                "${TMP_OPTION_OUTPUT_FOLDER}";

            # set folder permission to 700 to match what gpg does with it's
            # folders in making it more secure
            chmod \
                ${TMP_CHMOD_VERBOSITY} \
                700 \
                "${TMP_OPTION_OUTPUT_FOLDER}";

            # set a flag that we created the folder
            TMP_CREATED_OUTPUT_FOLDER=1;

            log_unquiet "Created output folder: ${TMP_OPTION_OUTPUT_FOLDER}";

        else
            abort "Output folder already exists: ${TMP_OPTION_OUTPUT_FOLDER}
Consider --recreate option." 1;
        fi

    else
        # create output folder
        mkdir \
            ${TMP_MKDIR_VERBOSITY} \
            --parent \
            "${TMP_OPTION_OUTPUT_FOLDER}";

        # set folder permission to 700 to match what gpg does with it's
        # folders in making it more secure
        chmod \
            ${TMP_CHMOD_VERBOSITY} \
            700 \
            "${TMP_OPTION_OUTPUT_FOLDER}";

        # set a flag that we created the folder
        TMP_CREATED_OUTPUT_FOLDER=1;

        log_unquiet "Created output folder: ${TMP_OPTION_OUTPUT_FOLDER}";
    fi
}


# ........................................................................... #
# Remove work folder if it is exists
function remove_work_folder {

    # remove the work for this script folder if exist
    if [ -d "${TMP_OPTION_WORK_FOLDER}" ]; then

        # shred all the files in the gpg homedir folder, cause private keys
        # and keyrings
        shred_recursively \
           "${TMP_SHRED_VERBOSITY}" \
           "${TMP_GPG_HOMEDIR_FOLDER}";

        # remove the work folder
        rm \
            ${TMP_RM_VERBOSITY} \
            --recursive \
            "${TMP_OPTION_WORK_FOLDER}";

        log_unquiet "Shredded and removed work folder: \
${TMP_OPTION_WORK_FOLDER}";

    fi

}


# ........................................................................... #
# create gpg.config file with no-random-seed-file config
# set gpg.config permissions to 600
function create_gpg_config_file {

    cat >"${TMP_GPG_CONF_FILE}" <<EOF
# do not add default keyrings
no-random-seed-file
EOF

    # change permission gor gpg.conf to the 600 for additional safety
    chmod \
        ${TMP_CHMOD_VERBOSITY} \
        600 \
        "${TMP_GPG_CONF_FILE}";

}


# ........................................................................... #
# import gpg key provided to the script
function import_gpg_key {

    # setup verbosity redirects for stdout using a file descriptor
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        exec 3>&1;
    else
        exec 3>/dev/null;
    fi

    # create keyrins and import the given gpg key
    "${TMP_OPTION_GPG}" \
        ${TMP_GPG_VERBOSITY} \
        --options "${TMP_GPG_CONF_FILE}" \
        --homedir "${TMP_GPG_HOMEDIR_FOLDER}" \
        --import \
        "${TMP_KEY_FILE}" \
    1>&3 \
    2>"${TMP_GPG_ERROR_LOG}" \
    || abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to create keyring and import gpg key file: ${TMP_KEY_FILE}" 1;

    # get the key id, record it to TMP_KEYID_FILE
    TMP_KEYID=$(\
        "${TMP_OPTION_GPG}" \
        --options "${TMP_GPG_CONF_FILE}" \
        --homedir "${TMP_GPG_HOMEDIR_FOLDER}" \
        --keyid-format short \
        --with-colons \
        --list-keys \
    | grep ^pub \
    | cut -d':' -f5) \
    2>"${TMP_GPG_ERROR_LOG}" \
    || abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to get KeyID for imported key, potentially failure importing" 1;

    # close out our custom file descriptor
    exec 3>&-;

}

# ........................................................................... #
# copy keyrings avoiding sockets, backups and other bits usually littering
# the gpg homedir. For >= gpg 2.1 this also copies the 'private-keys-v1.d'
# if present and security keyring is the same as public keyring
function copy_keyrings {

    # copy the keyring to the output folder preserving all attributes
    cp \
        ${TMP_CP_VERBOSITY} \
        --archive \
        "${TMP_KEYRING_FILE}" \
        "${TMP_OPTION_OUTPUT_FOLDER}" \
    || abort "Failed to copy keyring ring to output folder" 1;

    # if the two keyring paths are the same we are at >= gpg 2.1
    if [ "${TMP_KEYRING_FILE}" == "${TMP_SECRET_KEYRING_FILE}" ]; then

        # make sure the `private-keys-v1.d` exists
        if [ -d "${TMP_GPG_HOMEDIR_FOLDER}/private-keys-v1.d" ]; then
            # copy private-keys-v1.d to output folder preserving all attributes
            cp \
                ${TMP_CP_VERBOSITY} \
                --archive \
                --recursive \
                "${TMP_GPG_HOMEDIR_FOLDER}/private-keys-v1.d" \
                "${TMP_OPTION_OUTPUT_FOLDER}" \
            || abort "Failed to copy \"keyring private-keys-v1.d\" to output
folder" 1;
        fi
    else
        # copy secret keyring to the output folder preserving all attributes
        cp \
            ${TMP_CP_VERBOSITY} \
            --archive \
            "${TMP_SECRET_KEYRING_FILE}" \
            "${TMP_OPTION_OUTPUT_FOLDER}" \
        || abort "Failed to copy secret keyring ring to output folder" 1;
    fi

}


# ........................................................................... #
# get the file path for a given keyring type
# {1} string: keyring type (secret or public)
# Note: this method exists because keyrings in >= gpg 2.1 are named differently,
#       not to mention that there is now only one. In short, let have gpg tell
#       us where the keyrins are
# IMPORTANT: this method has to clean up the >= gpg 2.1 paths to look like
# <gpg2.1 ones since those seem to get prepended with pwd. fixing this is
# likely an overkill.
function get_keyring_file_path {

    local keyring_type="${1}";
    local key_list_argument;
    local keyring_file_path;
    local gpg2_unclean_path

    # setup verbosity redirects for stdout using a file descriptor
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        exec 3>&1;
    else
        exec 3>/dev/null;
    fi

    # set key_list_argument to --list-keys if keyring_type is public
    # set key_list_argument to --list-secret-keys if keyring_type is private
    # otherwise abort with an error message
    if [ "${keyring_type}" == "public" ]; then
        key_list_argument="--list-keys";
    elif [ "${keyring_type}" == "secret" ]; then
        key_list_argument="--list-secret-keys";
    else
        abort "get_keyring_file_path: keyring type not public, or secret" 1;
    fi

    # get the keyring using --list-options show-keyring and a list key option
    # specified in key_list_argument set above. It should be the first line
    # returned
    keyring_file_path=$("${TMP_OPTION_GPG}" \
        ${TMP_GPG_VERBOSITY} \
        --options "${TMP_GPG_CONF_FILE}" \
        --homedir "${TMP_GPG_HOMEDIR_FOLDER}" \
        --list-options show-keyring \
        ${key_list_argument} \
    | head -n 1) \
    2>"${TMP_GPG_ERROR_LOG}"  \
    || abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to get ${keyring_type} keyring file path" 1;

    #### commented out for now, not sure if we want clean path ###
    # clean up the path of any inderection and symlinks
    # >=gpg2.1 seems to concatenate homedir + path with relative paths
    # so it can look like this:
    # /tmp/../tmp/./tmp.gpg_keyring_importer/homedir/pubring.kbx
    # let's see if we can fix it by getting
    # local clean_keyring_file_path=$(
    #     cd "$(dirname ${keyring_file_path})";
    #     echo "$(pwd)/$(basename ${keyring_file_path})";
    # )
    # echo "${clean_keyring_file_path}";
    #### commented out for now, not sure if we want clean path ###

    # if we detect a gpg2 unclean path, try to print out the same combination
    # as gpg1 one (for now)
    gpg2_unclean_path="$(pwd)/${TMP_GPG_HOMEDIR_FOLDER}/";
    gpg2_unclean_path="${gpg2_unclean_path}$(basename ${keyring_file_path})";
    if [ "${keyring_file_path}" == "${gpg2_unclean_path}" ]; then
        echo "${TMP_GPG_HOMEDIR_FOLDER}/$(basename ${keyring_file_path})";
    else
        echo "${keyring_file_path}";
    fi

}


# ........................................................................... #
# print out keyring information
function print_keyring_information {

    local keyring="${TMP_OPTION_OUTPUT_FOLDER}/";
    keyring="${keyring}$(basename ${TMP_KEYRING_FILE})"

    local secret_keyring="${TMP_OPTION_OUTPUT_FOLDER}/";
    secret_keyring="${secret_keyring}$(basename ${TMP_SECRET_KEYRING_FILE})";

    if [ ${TMP_OPTION_MACHINE_READABLE} -eq 1 ]; then
        echo "keyring:${keyring}";
        echo "secret-keyring:${secret_keyring}";
        echo "imported-keyid:${TMP_KEYID}";
    else
        log_unquiet "Keyring        : ${keyring}";
        log_unquiet "Secret Keyring : ${secret_keyring}";
        log_unquiet "Imported KeyID : ${TMP_KEYID}";
        log_unquiet "GPG version    : $(gpg_version ${TMP_OPTION_GPG})";
    fi

}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ #
# import utils.sh
if [ -f "${TMP_SCRIPT_FOLDER}/utils.sh" ]; then
    source "${TMP_SCRIPT_FOLDER}/utils.sh"
else
    echo "
Could not load required '${TMP_SCRIPT_FOLDER}/utils.sh' module.$

" >&2;
    exit 1;
fi


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ #
begin "$@";
