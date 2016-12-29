#!/usr/bin/env bash

# Prerequisites:
# - gnu utils (apt-get install coreutils)
# - find (apt-get install findutils)
# - sed (apt-get install sed)
# - gpg, GPG key creator (apt-get install gnupg)
# - haveged, entropy generator (apt-get install haveged)

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

# get script name
TMP_SCRIPT_NAME=$(basename "${0}");
# get full path of the script folder
TMP_SCRIPT_FOLDER="$(cd $(dirname $0); pwd)";

# artly plugin display name
ARTLY_PLUGIN=${ARTLY_PLUGIN:-""}

# output folder
TMP_OPTION_OUTPUT_FOLDER="";
# gpg key type
TMP_OPTION_KEY_TYPE="";
# gpg key length
TMP_OPTION_KEY_LENGTH="";
# gpg subkey type
TMP_OPTION_SUBKEY_TYPE="";
# gpg subkey length
TMP_OPTION_SUBKEY_LENGTH="";
# gpg key real name
TMP_OPTION_NAME_REAL="";
# gpg key name comment
TMP_OPTION_NAME_COMMENT="";
# gpg key name email
TMP_OPTION_NAME_EMAIL="";
# gpg key name date
TMP_OPTION_EXPIRE_DATE="";
# path gpg binary
TMP_OPTION_GPG="";
# recreate the output folder flag
TMP_OPTION_RECREATE=0;
# machine output flag
TMP_OPTION_MACHINE_READABLE=0;
# script work folder
TMP_OPTION_WORK_FOLDER="";

TMP_OPTION_VERBOSE=0;
TMP_OPTION_QUIET=0;
TMP_OPTION_NO_COLOR=0;
TMP_OPTION_DEBUG=0;

# verbosity
TMP_GPG_VERBOSITY="";
TMP_RM_VERBOSITY="";
TMP_MKDIR_VERBOSITY="";
TMP_CHMOD_VERBOSITY="";
TMP_SHRED_VERBOSITY="";

# initialize homedir, gpg cong and gpg key script variable
# they will be updated by process_script_arguments
# also gpg error log to handle gpg stderr oddities
TMP_WORK_FOLDER_NAME_TEMPLATE="/tmp/artly-make-key.XXXXXXXXXX";
TMP_GPG_ERROR_LOG="";
TMP_GPG_HOMEDIR_FOLDER="";
TMP_GPG_CONF_FILE="";
TMP_GPG_KEY_SCRIPT="";
TMP_PRIVATE_KEY_FILE="";
TMP_PUBLIC_KEY_FILE="";
TMP_KEYID_FILE="";
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
${script_display_name} - generate GPG keys

Usage: ${script_display_name} [OPTIONS]

Generate GPG key and export armored versions of the keys out to the output
folder. The private key is exported into a file called 'private.asc' and the
public key is exported into 'public.asc' respectively. Additionally, a file
called keyid with the 16 charachter key id in it.

GPG key parameters can be provided on using arguments, though there are
reasonable (though incomplete) defaults.

Generating keys also requires a lot of entropy running to entropy generator
like haveged daemon running is encouraged (http://issihosts.com/haveged/).

To undestand GPG unattended generation please read:
https://www.gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html

Options:

    -o, --output-folder <path>
      Output folder for the generated keys.

    -n, --name-real <name>
      Name provided as Name-Real parameter to GPG. Part of user ID. See
      Unattended GPG generation notes for more information.

    -c, --name-comment <comment>
      Comment provided as Name-Comment parameter to GPG. Part of user ID. See
      Unattended GPG generation notes for more information.

    -e, --name-email <email>
      Email provided as Name-Email parameter to GPG. Part of user ID. See
      Unattended GPG generation notes for more information.

    -d, --expire-date <date>
      Expiration Date provided as Expire-Date parameter to GPG. See Unattended
      GPG generation notes for more information.

    -k, --key-type <key type>
        Optional, key type provided as Key-Type to GPG. By default set to
        \"RSA\". See Unattended GPG generation notes for more information.

    -l, --key-length <key length>
        Optional, key length as Key-Length to GPGP. By default set to 4096.
        NOTE: the larger the value the longer but more secure the key. See
        Unattended GPG generation notes for more information.

    -s, --subkey-type <key type>
        Optional, subkey type provided as Key-Type to GPG. By default set to
        \"ELG-E\". See Unattended GPG generation notes for more information.

    -L, --subkey-length <key length>
        Optional, subkey length as Subkey-Length to GPGP. By default set to
        4096. NOTE: the larger the value the longer but more secure the key.
        See Unattended GPG generation notes for more information.

    --gpg <gpg path>
        Optional, use the gpg executable specified by <gpg path>. By default
        set to the first gpg executble found on the PATH using \"type -P gpg\"
        command.

    --recreate
        Optional, delete previous output folder by the same name before
        creating it again. Useful when you want to recreate the keys without
        having to do manual removal.

    --machine-readable
        Optional, print out colon separated output. This only prints out the
        private key, public key and keyid.

    --work-folder <path>
        Optional, work folder path, needed to generate the keys. By default
        the work folder name is created by mktemp using following template
        \"${TMP_WORK_FOLDER_NAME_TEMPLATE}\".

        For more infomation and explanation of the template see \"man mktemp\".

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

    -h, --help
        show help for this script.

Notes:

    GPG generation is run with: no-random-seed-file
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

    # clear ERR trap so we do not hit recusions
    trap - ERR EXIT INT TERM;

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

    # log gpg key parameters
    log_gpg_parameters;

    # create folders
    create_folders;

    # create gpg config file
    create_gpg_config_file;

    # create gpg key script
    create_gpg_key_script;

    # generate gpg public, private keys and its keyid
    generate_gpg_keys;

    # if not debugging remove the work folder
    if [ ${TMP_OPTION_DEBUG} -eq 0 ]; then
        remove_work_folder;
    fi

    # print keyrings
    print_key_information;

}


# ............................................................................ #
# get script params and store them
function process_script_arguments {

    local short_args;
    local long_args="";
    local processed_args;

    short_args="o: n: c: e: d: k: l: s: L: v q h";
    long_args+="output-folder: name-real: name-comment: name-email: ";
    long_args+="key-type: key-length: subkey-type: subkey-length: ";
    long_args+="expire-date: gpg: recreate machine-readable work-folder: ";
    long_args+="verbose quiet no-color debug help";

    # if no arguments given print usage
    if [ $# -eq 0 ]; then
        usage 1>&2;
        echo "No argument givens">&2;
        exit 2;
    fi

    processed_args=$(get_getopt "${short_args}" "${long_args}" "$@") || \
        abort "Could not process options specified on command line
${processed_args}" 1;

    eval set -- "${processed_args}";

    # go over the arguments
    while [ $# -gt 0 ]; do
        case "$1" in

            # store output folder path
            --output-folder | -o)
                TMP_OPTION_OUTPUT_FOLDER="${2}";
                shift;
                ;;

            # store real name for gpg key
            --name-real | -n)
                TMP_OPTION_NAME_REAL="${2}";
                shift;
                ;;

            # store name comment for gpg key
            --name-comment | -c)
                TMP_OPTION_NAME_COMMENT="${2}";
                shift;
                ;;

            # store name email for gpg key
            --name-email |-e)
                TMP_OPTION_NAME_EMAIL="${2}";
                shift;
                ;;

            # store expiration date for gpg key
            --expire-date | -d)
                TMP_OPTION_EXPIRE_DATE="${2}";
                shift;
                ;;

            # store key type for gpg key
            --key-type | -k)
                TMP_OPTION_KEY_TYPE=="${2}"
                shift;
                ;;

            # store key length for gpg key
            --key-length | -l)
                TMP_OPTION_KEY_LENGTH="${2}"
                shift;
                ;;

            # store subkey type for gpg key
            --subkey-type | -s)
                TMP_OPTION_SUBKEY_TYPE="${2}";
                shift;
                ;;

            # store subkey length for gpg key
            --subkey-length | -L)
                TMP_OPTION_SUBKEY_LENGTH="${2}";
                shift;
                ;;

            # store gpg executable path
            --gpg)
                TMP_OPTION_GPG="${2}";
                shift;
                ;;

            # store recreate flag
            --recreate)
                TMP_OPTION_RECREATE=1;
                ;;

            # store machine readable flag
            --machine-readable)
                TMP_OPTION_MACHINE_READABLE=1;
                ;;

            # store work folder path
            --work-folder)
                TMP_OPTION_WORK_FOLDER="${2}";
                # remove the value argument from the stack
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

            # show usage and quit with code 1
            --help | -h)
                usage;
                exit 1;
                ;;

            --)
                # is the end marker from getopt
                shift;
                # there should not be any trailing params
                if [ "${#}" -gt 0 ]; then
                    # print usage to stderr since no valid command was provided
                    usage 1>&2;
                    echo "Unknown arguments(s) '$@' given">&2;
                    exit 2;
                else
                    # if it 0 then break the loop, so the shift at the end
                    # of the for loop did not cause an error
                    break;
                fi
                ;;

            -*)
                # print usage to stderr since no valid command was provided
                usage 1>&2;
                echo "Unknown argument(s) '${1}' given.">&2;
                exit 2;
                ;;

            *)
                # print usage to stderr since no valid command was provided
                usage 1>&2;
                echo "No arguments given">&2;
                exit 2;
                ;;
        esac
        shift;
    done

}


# ........................................................................... #
# validate the set script arguments and set all default values that are
# not set at the top of the script when variable containing them are declared
function validate_and_default_arguments {

    # output folder for the keys
    if [ "${TMP_OPTION_OUTPUT_FOLDER}" == "" ]; then
        abort "Please specify  output folder using --output-folder/-o" 1;
    fi

    # set key type default to RSA
    if [ "${TMP_OPTION_KEY_TYPE}" == "" ]; then
        TMP_OPTION_KEY_TYPE="RSA";
    fi

    # set key length default to 4096
    if [ "${TMP_OPTION_KEY_LENGTH}" == "" ]; then
        TMP_OPTION_KEY_LENGTH=4096;
    fi

    # set subkey type default to ELG-E
    if [ "${TMP_OPTION_SUBKEY_TYPE}" == "" ]; then
        TMP_OPTION_SUBKEY_TYPE="ELG-E";
    fi

    # set subkey length default to 4096
    if [ "${TMP_OPTION_SUBKEY_LENGTH}" == "" ]; then
        TMP_OPTION_SUBKEY_LENGTH=4096;
    fi

    # if name-real is not given abort
    if [ "${TMP_OPTION_NAME_REAL}" == "" ]; then
        abort "Please specify name using --name-real/-n" 1;
    fi

    # if name comment is not given abort
    if [ "${TMP_OPTION_NAME_COMMENT}" == "" ]; then
        abort "Please specify comment using --name-comment/-c" 1;
    fi

    # if name email is not given abort
    if [ "${TMP_OPTION_NAME_EMAIL}" == "" ]; then
        abort "Please specify email --name-email/-e" 1;
    fi

    # if expire date is not given abort
    if [ "${TMP_OPTION_EXPIRE_DATE}" == "" ]; then
        abort "Please specify expiration date using --expire-date/-d" 1;
    fi

    # default virtualenv to gpg executable
    if [ "${TMP_OPTION_GPG}" == "" ]; then
        TMP_OPTION_GPG="$(type -P gpg)";
    fi
    # check if gpg we have found exists
    cmds_exists_or_abort "${TMP_OPTION_GPG}";

    # default work folder to <script folder>/tmp.<simple name>
    # for more info on simple name see above
    # TODO: switch to temp folder name generations
    if [ "${TMP_OPTION_WORK_FOLDER}" == "" ]; then
        TMP_OPTION_WORK_FOLDER="$(\
          mktemp \
            --directory \
            --dry-run \
            ${TMP_WORK_FOLDER_NAME_TEMPLATE}
        )";
    fi

    # if debug then turn on verbosity
    if [ ${TMP_OPTION_DEBUG} -eq 1 ]; then
        TMP_OPTION_VERBOSE=1;
    fi

    # if verbose the set gpg, rm, mkdir, chmod shred verbosity
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        TMP_GPG_VERBOSITY="--verbose";
        TMP_RM_VERBOSITY="--verbose";
        TMP_MKDIR_VERBOSITY="--verbose";
        TMP_CHMOD_VERBOSITY="--verbose";
        TMP_SHRED_VERBOSITY="--verbose";
    else
        TMP_GPG_VERBOSITY="";
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
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
        TMP_CHMOD_VERBOSITY="--quiet";
        TMP_SHRED_VERBOSITY="";
    fi

    # gpg error log, only available after work folder has been created
    TMP_GPG_ERROR_LOG="${TMP_OPTION_WORK_FOLDER}/gpg_error.log"
    # home dir use to "sandbox" execution of gpg
    TMP_GPG_HOMEDIR_FOLDER="${TMP_OPTION_WORK_FOLDER}/gpg_homedir";
    # gpg.conf options file
    TMP_GPG_CONF_FILE="${TMP_GPG_HOMEDIR_FOLDER}/gpg.conf";
    # gpg key creation script
    TMP_GPG_KEY_SCRIPT="${TMP_OPTION_WORK_FOLDER}/gpg_key.script";

    # full path for private, public keys and their keyid files
    TMP_PRIVATE_KEY_FILE="${TMP_OPTION_OUTPUT_FOLDER}/private.asc";
    TMP_PUBLIC_KEY_FILE="${TMP_OPTION_OUTPUT_FOLDER}/public.asc";
    TMP_KEYID_FILE="${TMP_OPTION_OUTPUT_FOLDER}/keyid";

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
        "echo" "basename" "dirname" "mkdir" "rm" "rev" "grep" "find" "shred";

}


# ............................................................................ #
# log paths and various scripts information
function log_script_info {

    log_verbose "Output folder : ${TMP_OPTION_OUTPUT_FOLDER}";
    log_verbose "GPG executable: ${TMP_OPTION_GPG}";
    log_verbose "GPG version   : $(gpg_version ${TMP_OPTION_GPG})";
    log_verbose "Work folder   : ${TMP_OPTION_WORK_FOLDER}";
    log_verbose "GPG homedir   : ${TMP_GPG_HOMEDIR_FOLDER}";
    log_verbose "gpg.conf      : ${TMP_GPG_CONF_FILE}";
    log_verbose "GPG key script: ${TMP_GPG_KEY_SCRIPT}";
    log_verbose "Private key   : ${TMP_PRIVATE_KEY_FILE}";
    log_verbose "Public key    : ${TMP_PUBLIC_KEY_FILE}";
    log_verbose "KeyID file    : ${TMP_KEYID_FILE}";
    log_verbose "Recreate      : $(humanize_bool ${TMP_OPTION_RECREATE})";
    log_verbose "Debug         : $(humanize_bool ${TMP_OPTION_DEBUG})";
}


# ............................................................................ #
# log GPG parameters
function log_gpg_parameters {
    log_verbose "Key-Type     : ${TMP_OPTION_KEY_TYPE}";
    log_verbose "Key-Length   : ${TMP_OPTION_KEY_LENGTH}";
    log_verbose "Subkey-Type  : ${TMP_OPTION_SUBKEY_TYPE}";
    log_verbose "Subkey-Length: ${TMP_OPTION_SUBKEY_LENGTH}";
    log_verbose "Name-Real    : ${TMP_OPTION_NAME_REAL}";
    log_verbose "Name-Comment : ${TMP_OPTION_NAME_COMMENT}";
    log_verbose "Name-Email   : ${TMP_OPTION_NAME_EMAIL}";
    log_verbose "Expire-Date  : ${TMP_OPTION_EXPIRE_DATE}";
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

    # create gpg homedir folder
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
    echo "" > "${TMP_GPG_CONF_FILE}";
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
# create GPG key script in unattanded manner
# with following settings:
# key type RSA 4096 + ELG-E 4069
# Real Name : Cars Santa Monica Development and Operations Team
# Comment: Debian Repository
# Email: sm-ops@cars.com
# Expiration: does not expire (this is probably wrong)
function create_gpg_key_script {

    cat >"${TMP_GPG_KEY_SCRIPT}" <<EOF
%echo Generating a signing OpenPGP key
Key-Type: ${TMP_OPTION_KEY_TYPE}
Key-Length: ${TMP_OPTION_KEY_LENGTH}
Subkey-Type: ${TMP_OPTION_SUBKEY_TYPE}
Subkey-Length: ${TMP_OPTION_SUBKEY_LENGTH}
Name-Real: ${TMP_OPTION_NAME_REAL}
Name-Comment: ${TMP_OPTION_NAME_COMMENT}
Name-Email: ${TMP_OPTION_NAME_EMAIL}
Expire-Date: ${TMP_OPTION_EXPIRE_DATE}
# disable passphrase protection (required in gpg  2.1 and up)
%no-protection
%commit
%echo Finished generating OpenPGP key!
EOF

    log_verbose "GPG Key Script File: "${TMP_GPG_KEY_SCRIPT}""
    cat_verbose "${TMP_GPG_KEY_SCRIPT}";

}


# ........................................................................... #
# generate gpg key using out custom script and homedir
function generate_gpg_keys {

    # keyid for generated key
    local keyid;

    # setup verbosity redirects for stdout using a file descriptor
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        exec 3>&1;
    else
        exec 3>/dev/null;
    fi

    # show available entropy
    log_unquiet \
        "Available entropy: $(cat /proc/sys/kernel/random/entropy_avail)";
    log_unquiet "If you entropy is low this may take a while. Make sure you \
have \"haveged\" service running";

    # generate the key and place it in the keyring
    "${TMP_OPTION_GPG}" \
        ${TMP_GPG_VERBOSITY} \
        --options "${TMP_GPG_CONF_FILE}" \
        --homedir "${TMP_GPG_HOMEDIR_FOLDER}" \
        --batch \
        --gen-key \
        "${TMP_GPG_KEY_SCRIPT}" \
    1>&3 \
    2>"${TMP_GPG_ERROR_LOG}" \
    || abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to generate keyring with a new key" 1;

    # extract the keyid using the public file into a GPG_KEY_NAME.keyid file
    # produce output with colons, grep for first public key & return 5th field.
    # this runs in subshell so we can combine stderr more easily
    # IMPORTANT: this also relies on "set -o pipeline so not to fail"
    # on overall this is completely terrible for error message debugging
    # since gpg dumps unrelated information into stderr, while grep and cut
    # print NO relevant information into stderr
    (
        "${TMP_OPTION_GPG}" \
            --options "${TMP_GPG_CONF_FILE}" \
            --homedir "${TMP_GPG_HOMEDIR_FOLDER}" \
            --keyid-format short \
            --with-colons \
            --list-keys \
        | grep ^pub \
        | cut -d':' -f5 \
        1>"${TMP_KEYID_FILE}"
    ) 2>"${TMP_GPG_ERROR_LOG}" \
    || abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to find keyid in the keyring & record to ${TMP_KEYID_FILE}" 1;

    # put keyid in the variable
    keyid="$(cat ${TMP_KEYID_FILE})";

    # export armored public key using the keyid in the keyid file to
    # TMP_PUBLIC_KEY_FILE. use --batch so it does not prompt, because it does.
    # so not for the sadness: if gpg fails to export the key it will actuallly
    # print 'gpg: WARNING: nothing exported' to stderr but will still exit
    # with code 0, effectively telling us all is good. As such we will need to
    # do our own check, checking if the file itself was generated
    "${TMP_OPTION_GPG}" \
        ${TMP_GPG_VERBOSITY} \
        --options "${TMP_GPG_CONF_FILE}" \
        --homedir "${TMP_GPG_HOMEDIR_FOLDER}" \
        --batch \
        --export \
        --armor \
        --output "${TMP_PUBLIC_KEY_FILE}" \
        "${keyid}" \
    1>&3 \
    2>"${TMP_GPG_ERROR_LOG}" \
    || abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to export armored public key to ${TMP_PUBLIC_KEY_FILE}" 1;
    # check if public key file was actually created and if not abort
    if [ ! -f "${TMP_PUBLIC_KEY_FILE}" ]; then
        abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to export armored public key to ${TMP_PUBLIC_KEY_FILE}" 1;
    fi

    # export armored private key using the keyid in the keyid file into
    # TMP_PUBLIC_KEY_FILE. use --batch so it does not prompt, because it does.
    # so not for the sadness: if gpg fails to export the key it will actuallly
    # print 'gpg: WARNING: nothing exported' to stderr but will still exit
    # with code 0, effectively telling us all is good. As such we will need to
    # do our own check, checking if the file itself was generated
    "${TMP_OPTION_GPG}" \
        ${TMP_GPG_VERBOSITY} \
        --options "${TMP_GPG_CONF_FILE}" \
        --homedir "${TMP_GPG_HOMEDIR_FOLDER}" \
        --export-secret-keys \
        --armor \
        --output "${TMP_PRIVATE_KEY_FILE}" \
        "${keyid}" \
    1>&3 \
    2>"${TMP_GPG_ERROR_LOG}" \
    || abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to export armored private key to ${TMP_PRIVATE_KEY_FILE}" 1;
    # check if private key file was actually created and if not abort
    if [ ! -f "${TMP_PRIVATE_KEY_FILE}" ]; then
        abort_with_log \
        "${TMP_GPG_ERROR_LOG}" \
        "failed to export armored private key to ${TMP_PRIVATE_KEY_FILE}" 1;
    fi

    # change permission for private key to 600 (user rw) for security
    chmod \
        ${TMP_CHMOD_VERBOSITY} \
        600 \
        "${TMP_PRIVATE_KEY_FILE}";

    # close out our custom file descriptor
    exec 3>&-;

}


# ........................................................................... #
# print out keyring information
function print_key_information {

    local keyid="$(cat ${TMP_KEYID_FILE})";

    if [ ${TMP_OPTION_MACHINE_READABLE} -eq 1 ]; then
        echo "private-key:${TMP_PRIVATE_KEY_FILE}";
        echo "public-key:${TMP_PUBLIC_KEY_FILE}";
        echo "keyid:${keyid}";
        echo "keyid-file:${TMP_KEYID_FILE}";
    else
        echo "Private key: ${TMP_PRIVATE_KEY_FILE}";
        echo "Public key : ${TMP_PUBLIC_KEY_FILE}";
        echo "KeyID      : ${keyid}";
        echo "KeyID file : ${TMP_KEYID_FILE}";
        echo "GPG version: $(gpg_version ${TMP_OPTION_GPG})";
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
