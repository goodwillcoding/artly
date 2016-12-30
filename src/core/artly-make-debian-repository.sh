#!/usr/bin/env bash

# Prerequisites:
# - gnu utils (apt-get install coreutils)
# - find (apt-get install findutils)
# - sed (apt-get install sed)
# - gpg, GPG key creator (apt-get install gnupg2)
# - aptly, debian repo creator (installation: https://www.aptly.info/download/)
# - wget, http download utility (apt-get install wget)
# - jq, json utility (apt-get install jq)
# - haveged, entropy generator (apt-get install haveged)

# TODO: what happens when there is a clobber of the file during attempt to
#       download it, do we error out and how?

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


# ........................................................................... #
# get script name
TMP_SCRIPT_NAME=$(basename "${0}");
# get full path of the script folder
TMP_SCRIPT_FOLDER="$(cd $(dirname $0); pwd)";

# artly plugin display name, extracted from environment otherwise set to ""
ARTLY_PLUGIN=${ARTLY_PLUGIN:-""}


# ........................................................................... #
# variables to store script arguments in
# static defaults are set here
# dynamic ones, which are based on other passed in parameters are set in
# process_script_arguments
# TODO: figure out a better way, prolly use -z
TMP_OPTION_OUTPUT_FOLDER="";
TMP_OPTION_REPOSITORY_NAME="";
TMP_OPTION_REPOSITORY_COMPONENT="";
TMP_OPTION_REPOSITORY_DISTRIBUTION="";
TMP_SECRET_KEY_FILE="";
declare -a TMP_OPTION_PACKAGE_ENTITIES;
TMP_OPTION_REPOSITORY_ARCHITECTURES="";
TMP_OPTION_REPOSITORY_LABEL="";
TMP_OPTION_REPOSITORY_ORIGIN="";
TMP_OPTION_REPOSITORY_DESCRIPTION="";
TMP_OPTION_PUBLIC_KEY_FILE="";
TMP_OPTION_RECREATE=0;
TMP_OPTION_GPG="";
TMP_OPTION_WORK_FOLDER="";
TMP_OPTION_MACHINE_READABLE=0;

TMP_OPTION_VERBOSE=0;
TMP_OPTION_QUIET=0;
TMP_OPTION_NO_COLOR=0;
TMP_OPTION_DEBUG=0;

# verbosity
TMP_WGET_VERBOSITY="";
TMP_GPG_VERBOSITY="";
TMP_RM_VERBOSITY="";
TMP_MKDIR_VERBOSITY="";
TMP_MV_VERBOSITY="";
TMP_CP_VERBOSITY="";
TMP_CHMOD_VERBOSITY="";
TMP_SHRED_VERBOSITY="";

# template for the work folder name
TMP_WORK_FOLDER_NAME_TEMPLATE="/tmp/artly-make-debian-repository.XXXXXXXXXX";

# folder for downloaded packages and copied
TMP_SOURCE_FOLDER="";
# file containing all package enteties (folders, files) to import after
# they been scanned and imported
TMP_PACKAGE_LIST_FILE="";

# aptly work, rootdir and config file
# also the log file for the package import process
TMP_APTLY_IMPORT_LOG="";
TMP_APTLY_WORK_FOLDER=""
TMP_APTLY_ROOTDIR_FOLDER="";
TMP_APTLY_CONFIG_FILE="";

# bin folder for the gpg wrapper
TMP_BIN_FOLDER="";

# keyrings file paths, keyid of the imported key file, imported packages count
TMP_PUBLIC_KEY_FILE="";
TMP_KEYRING_FILE="";
TMP_SECRET_KEYRING_FILE="";
TMP_KEYID="";
TMP_IMPORTED_PACKAGES_COUNT="";

# flag to track if we created the output folder, necessary because of the
# error trapping removing the folder when we did not create it
# default to 0 so this way we do not remove the folder
TMP_CREATED_OUTPUT_FOLDER=0;


# ........................................................................... #
# print script usage
function usage {

    local script_display_name;

    if [ "${ARTLY_PLUGIN}" == "" ]; then
        script_display_name="${TMP_SCRIPT_NAME}";
    else
        script_display_name="${ARTLY_PLUGIN}";
    fi

    echo "\
${script_display_name} - generate and sign Debian package repository

Usage: ${script_display_name} [OPTIONS]

Generate GPG keyring and import it's private, public and keyid into output
folder. Key parameters can be provided on using arguments, though there are
reasonable (though incomplete) defaults.

To understand Debian repository format please read:
https://wiki.debian.org/RepositoryFormat

Options:

    -o, --output-folder <path>
        Repository output folder.

    -n, --name
        Repository name.

    -d, --distribution
        Repository distribution.

    -c, --component
        Repository component.

    -k, --secret-key-file <path>
        Secret key file path. Secret PGP key to sign the repository with.

    -p, --package-location <path>
        Semi-optional, path to local package files or a folders to be scanned
        recursively for packages to import into the repository.

        If you want to specify multiple files of folder quote the argument
        like so: --package-location \"./folder1 /folder2\".

        You can also specify this argument multiple times:
        --package-location \"./folder1 /folder2\" --package-location ./folder3

        IMPORTANT: at least one --package-location or --package-url needs to be
        specified.

    -u, --package-url <url>
        Semi-optional, URL of the package to download and import to the
        repository.

        Same as with --package-location/-p you can specify multiple URLs
        within quotes and can specify --package-url/-u argument multiple times.

        IMPORTANT: at least one --package-location or --package-url needs to be
        specified.

    -a, --architectures
        Optional, repository architectures to publish. By default set to
        'amd64,i386,all,source' which publishes \"amd64\", \"i386\"
        architectures, architecture-independent \"all\" packages and source
        packages. (see Notes Sections for explanation).

        Multiple values should be comma separated without spaces if you do not
        quote them (example -a amd64,i686). Quote the argument \"amd64, i686\"
        if you have spaces.

    --label
        Optional, repository label.

    --origin
        Optional, repository origin.

    --description
        Optional, repository description. If omitted, filled out by aptly
        with it's friendly \"Generated by aptly\" message.

    --public-key <path>
        Optional, file path to the exported public key of the secret key used
        to sign the repository. By default set to \"public.asc\" which means it
        will be placed inside the output folder.

        Common recommended key extension is \".asc\".

        Also the key path must be relative to the output folder and not start
        with \"/\" or contain any \"..\" parts.

    --gpg <gpg path>
        Optional, use the gpg executable specified by <gpg path>. By default
        set to the first gpg executable found on the PATH using \"type -P gpg\"
        command.

    --machine-readable
        Optional, print out colon separated output. This only prints out
        repository information.

    --recreate
        Optional, delete previous output folder by the same name before
        creating it again. Useful when you want to recreate the keys without
        having to do manual removal.

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

    -h, --help
        show help for this script.

Notes:

    Currently aptly 0.9.7 is unable to publish a repository if all the debian
    packages are architecture independent (a.k.k \"all\" architecture)
    See: https://github.com/smira/aptly/issues/165
    As such we have to force specifying architecture and defaulting it to
    VERY common ones.
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


# ........................................................................... #
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

    # create folders
    create_folders;

    # download packages
    generate_package_list;

    # create aptly config
    create_aptly_config;

    # create new repository
    create_new_repository;

    # import debian packages into the repository
    import_debian_packages_into_repository;

    # create keyrings with an imported secret key file
    create_keyrings;

    # create gpg.conf with with keyring information
    create_gpg_config_file;

    # create gpg executable
    create_gpg_wrapper;

    # publish repository
    publish_repository;

    # export public key;
    export_public_key

    # if not debugging remove the work folder
    if [ ${TMP_OPTION_DEBUG} -eq 0 ]; then
        remove_work_folder;
    fi

    # print repository information
    print_repository_information
}

# ........................................................................... #
# checks for all the commands required for setup and activate
# this does not include the python commands we install
function check_commands {

    local current_aptly_version;
    local required_aptly_version;

    # check for bash 4
    cmd_exists_bash4_or_abort;

    # check gnu getop
    cmd_exists_gnu_getopt_or_abort;

    # check for a whole set of commands
    cmds_exists_or_abort \
        "echo" "basename" "dirname" "mkdir" "rm" "rev" "cut" "grep" \
        "find" "sed" "shred" "wget" "jq" "aptly";

    # get current aptly version and compare it to the one we want
    current_aptly_version="$(aptly version | sed 's/aptly version: //g')"
    required_aptly_version="0.9.7";
    version_lte "${required_aptly_version}" "${current_aptly_version}" \
    || abort "Aptly version ${current_aptly_version} is below required \
version ${required_aptly_version}" 1;

}


# ........................................................................... #
# get script params and store them
function process_script_arguments {
    local short_args;
    local long_args="";
    local processed_args;

    short_args="o: n: d: c: k: p: u: a: v q h";
    long_args+="output-folder: name: distribution: component: ";
    long_args+="secret-key-file: package-location: package-url: ";
    long_args+="architectures: label: origin: description: public-key: ";
    long_args+="gpg: recreate machine-readable work-folder: verbose quiet ";
    long_args+="debug help";

    # if no arguments given print usage
    if [ $# -eq 0 ]; then
        # print usage to stderr since no valid command was provided
        usage 1>&2;
        echo "No arguments given">&2;
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

            # store repository name
            --name | -n)
                TMP_OPTION_REPOSITORY_NAME="${2}";
                shift;
                ;;

            # store repository distribution
            --distribution | -d)
                TMP_OPTION_REPOSITORY_DISTRIBUTION="${2}";
                shift;
                ;;

            # store repository component
            --component | -c)
                TMP_OPTION_REPOSITORY_COMPONENT="${2}";
                shift;
                ;;

            # store secret key file path
            --secret-key-file | -k)
                TMP_SECRET_KEY_FILE="${2}";
                shift;
                ;;

            # store package location in an array
            --package-location | -p)
                TMP_OPTION_PACKAGE_ENTITIES+=("${1}:${2}")
                shift;
                ;;

            # store package url in an array
            --package-url | -u)
                TMP_OPTION_PACKAGE_ENTITIES+=("${1}:${2}")
                shift;
                ;;

            # store repository architectures
            --architectures | -a)
                TMP_OPTION_REPOSITORY_ARCHITECTURES="${2}";
                shift;
                ;;

            # store repository label
            --label)
                TMP_OPTION_REPOSITORY_LABEL="${2}";
                shift;
                ;;

            # store repository origin
            --origin)
                TMP_OPTION_REPOSITORY_ORIGIN="${2}";
                shift;
                ;;

            # store repository description
            --description)
                TMP_OPTION_REPOSITORY_DESCRIPTION="${2}";
                shift;
                ;;

            # store exported public key
            --public-key)
                TMP_OPTION_PUBLIC_KEY_FILE="${2}";
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

            # store work folder path
            --work-folder)
                TMP_OPTION_WORK_FOLDER="${2}";
                shift
                ;;

            # store machine readable flag
            --machine-readable)
                TMP_OPTION_MACHINE_READABLE=1;
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

            # show usage and quit with code 0
            --help | -h)
                usage;
                exit 0;
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
                echo "No arguments given.">&2;
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

    local public_key_check_bad_parts_check;

    # check if repository name is specified, if not abort with message
    if [ "${TMP_OPTION_REPOSITORY_NAME}" == "" ]; then
        abort "Please specify repository name using --name/-n" 1;
    fi

    # check if repository distribution is specified, if not abort with message
    if [ "${TMP_OPTION_REPOSITORY_DISTRIBUTION}" == "" ]; then
        abort \
            "Please specify repository distribution using --distribution/-d" 1;
    fi

    # check if repository component is specified, if not abort with message
    if [ "${TMP_OPTION_REPOSITORY_COMPONENT}" == "" ]; then
        abort "Please specify repository component using --component/-c" 1;
    fi

    # set the default to the common "amd64, all,source" see usage notes for
    # explanation
    if [ "${TMP_OPTION_REPOSITORY_ARCHITECTURES}" == "" ]; then
        TMP_OPTION_REPOSITORY_ARCHITECTURES="amd64,i386,all,source";
    fi

    # check if keyfile is specified, if not abort with message
    if [ "${TMP_SECRET_KEY_FILE}" == "" ]; then
        abort "Please specify secret key file using --secret-key-file/-k" 1;
    fi

    # check if the TMP_OPTION_PACKAGE_ENTITIES is empty, if so then no
    # package entries were specified.
    if [ ${#TMP_OPTION_PACKAGE_ENTITIES[@]} -eq 0 ]; then
        abort "Please specify at least one package source using --package-url \
or --package-location" 1;
    fi

    # check if output folder is specified, if not abort with message
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

    # public key to export, set default if not set
    # also check for ../
    if [ "${TMP_OPTION_PUBLIC_KEY_FILE}" == "" ]; then
        TMP_OPTION_PUBLIC_KEY_FILE="public.asc";
    else
        # get pipe error code safe (using || true) error code of the grep
        # for bad patterns
        public_key_check_bad_parts_check=$(\
            echo "${TMP_OPTION_PUBLIC_KEY_FILE}" \
            | grep \
                --extended-regexp \
                "/\.\.|\.\./|^/" \
            1>/dev/null \
            2>/dev/null;
            echo $?) \
        || true;

        # if we found the patterns grep would exit with 0 as such abort
        if [ ${public_key_check_bad_parts_check} -eq 0 ]; then
            abort "Please specify exported public key path that does not \
start with / and without \"..\" parts" 1
        fi
    fi
    # set TMP_PUBLIC_KEY_FILE to the full path
    TMP_PUBLIC_KEY_FILE="${TMP_OPTION_OUTPUT_FOLDER}/${TMP_OPTION_PUBLIC_KEY_FILE}";

    # if debug then turn on verbosity
    if [ ${TMP_OPTION_DEBUG} -eq 1 ]; then
        TMP_OPTION_VERBOSE=1;
    fi

    # if verbose the set gpg, rm, mkdir verbosity
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        TMP_WGET_VERBOSITY="--verbose"
        TMP_GPG_VERBOSITY="--verbose";
        TMP_RM_VERBOSITY="--verbose";
        TMP_MKDIR_VERBOSITY="--verbose";
        TMP_MV_VERBOSITY="--verbose";
        TMP_CP_VERBOSITY="--verbose";
        TMP_CHMOD_VERBOSITY="--verbose";
        TMP_SHRED_VERBOSITY="--verbose";
    else
        TMP_WGET_VERBOSITY="";
        TMP_GPG_VERBOSITY="";
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
        TMP_MV_VERBOSITY="";
        TMP_CP_VERBOSITY="";
        TMP_CHMOD_VERBOSITY="";
        TMP_SHRED_VERBOSITY="";
    fi

    # if quiet, set verbosity to 0 and enforce the quietest options for
    # those utilities that have it (gpg, rm, mkdir, mv, chmod)
    if [ ${TMP_OPTION_QUIET} -eq 1 ]; then
        TMP_OPTION_VERBOSE=0;

        TMP_WGET_VERBOSITY="--quiet";
        TMP_GPG_VERBOSITY="--quiet";
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
        TMP_MV_VERBOSITY="";
        TMP_CP_VERBOSITY="";
        TMP_CHMOD_VERBOSITY="--quiet";
        TMP_SHRED_VERBOSITY="";
    fi


    # packages
    TMP_SOURCE_FOLDER="${TMP_OPTION_WORK_FOLDER}/packages_source";
    TMP_PACKAGE_LIST_FILE="${TMP_OPTION_WORK_FOLDER}/package_entities.txt";

    # gpg error log, only available after work folder has been created
    TMP_APTLY_IMPORT_LOG="${TMP_OPTION_WORK_FOLDER}/aptly_import.log"
    # work and roodir folder and config file for aptly
    TMP_APTLY_WORK_FOLDER="${TMP_OPTION_WORK_FOLDER}/aptly"
    TMP_APTLY_ROOTDIR_FOLDER="${TMP_APTLY_WORK_FOLDER}/rootdir";
    TMP_APTLY_CONFIG_FILE="${TMP_APTLY_WORK_FOLDER}/aptly.conf";

    # home dir use to "sandbox" execution of gpg
    TMP_GPG_HOMEDIR_FOLDER="${TMP_OPTION_WORK_FOLDER}/gpg_homedir";
    # gpg.conf options file
    TMP_GPG_CONF_FILE="${TMP_GPG_HOMEDIR_FOLDER}/gpg.conf";
    # bin folder for the gpg script
    TMP_BIN_FOLDER="${TMP_OPTION_WORK_FOLDER}/bin";

}


# ........................................................................... #
# log paths and various scripts information
function log_script_info {


    log_verbose "Repository Name          : ${TMP_OPTION_REPOSITORY_NAME}";
    log_verbose "Repository Distribution  : ${TMP_OPTION_REPOSITORY_DISTRIBUTION}";
    log_verbose "Repository Component     : ${TMP_OPTION_REPOSITORY_COMPONENT}";
    log_verbose "Repository Architectures : ${TMP_OPTION_REPOSITORY_ARCHITECTURES}";
    log_verbose "Secret Key file          : ${TMP_SECRET_KEY_FILE}";
    log_verbose "Output folder            : ${TMP_OPTION_OUTPUT_FOLDER}";
    log_verbose "Repository Label         : ${TMP_OPTION_REPOSITORY_LABEL}";
    log_verbose "Repository Origin        : ${TMP_OPTION_REPOSITORY_ORIGIN}";
    if [ "${TMP_OPTION_REPOSITORY_DESCRIPTION}" == "" ]; then
        log_verbose "Repository Description   : ${TMP_OPTION_REPOSITORY_DESCRIPTION}";
    fi
    log_verbose "Recreate                 : $(humanize_bool ${TMP_OPTION_RECREATE})";
    log_verbose "GPG executable           : ${TMP_OPTION_GPG}";
    log_verbose "GPG version              : $(gpg_version ${TMP_OPTION_GPG})";
    log_verbose "Public Key                : ${TMP_PUBLIC_KEY_FILE}";
    log_verbose "Work folder              : ${TMP_OPTION_WORK_FOLDER}";
    log_verbose "GPG homedir              : ${TMP_GPG_HOMEDIR_FOLDER}";
    log_verbose "gpg.conf                 : ${TMP_GPG_CONF_FILE}";
    log_verbose "Debug                    : $(humanize_bool ${TMP_OPTION_DEBUG})";

    for package_entity in "${TMP_OPTION_PACKAGE_ENTITIES[@]}"; do
        package_type="$(echo ${package_entity} | cut -d':' -f1)";
        package_location="$(echo ${package_entity} | cut -d':' -f2-)";
        log_verbose "${package_type} : ${package_location}";
    done

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

    # remove work folder if exists, forcing removal if recreate flag is set
    remove_work_folder;
    # create work folder
    mkdir \
        ${TMP_MKDIR_VERBOSITY} \
        --parent \
        "${TMP_OPTION_WORK_FOLDER}";
    log_unquiet "Created work folder: ${TMP_OPTION_WORK_FOLDER}";

    # create source folder for the packages
    mkdir \
        --parent \
        "${TMP_SOURCE_FOLDER}";

    # create aptly work folder
    mkdir \
        --parent \
        "${TMP_APTLY_WORK_FOLDER}";

    # create aptly rootdir
    mkdir \
        --parent \
        "${TMP_APTLY_ROOTDIR_FOLDER}";

    # create bin folder for gpg executable
    mkdir \
        ${TMP_MKDIR_VERBOSITY} \
        --parent \
        "${TMP_BIN_FOLDER}";

}


# ........................................................................... #
# create output folder, remove it if already exists and recreate is true
# otherwise abort suggesting recreate option
function create_output_folder {

    if [ -d "${TMP_OPTION_OUTPUT_FOLDER}" ]; then

        if [ ${TMP_OPTION_RECREATE} -eq 1 ]; then
            # remove the output folder
            rm \
                ${TMP_RM_VERBOSITY} \
                --recursive \
                "${TMP_OPTION_OUTPUT_FOLDER}";
            log_unquiet "Removed output folder: ${TMP_OPTION_OUTPUT_FOLDER}";

            # create output folder
            mkdir \
                ${TMP_MKDIR_VERBOSITY} \
                --parent \
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

        rm \
            ${TMP_RM_VERBOSITY} \
            --recursive \
            "${TMP_OPTION_WORK_FOLDER}";

        log_unquiet "Shredded and removed work folder: \
${TMP_OPTION_WORK_FOLDER}";

    fi

}


# ........................................................................... #
# retrieve package from various locations into the source folder for import
# do not clobber files if the already exist
function generate_package_list {

    local package_type;
    local package_locations;
    local package_file;

    # go over each package entity and get it's type and locations
    for package_entities_entry in "${TMP_OPTION_PACKAGE_ENTITIES[@]}"; do

        package_type="$(echo ${package_entities_entry} | cut -d':' -f1)";
        package_locations="$(echo ${package_entities_entry} | cut -d':' -f2-)";

        # go over each location and add it to the TMP_PACKAGE_LIST_FILE
        # download files as necessary and do validation on the paths
        for package_location in ${package_locations}; do
            case "${package_type}" in

                # validate the package_location exists and add it the package
                # list. if this is a folder aptly will scan the folder
                # recursively so just add this locations
                --package-location | -p)
                    if [ ! -e "${package_location}" ]; then
                        abort "Following file or folder specified by ${package_type} is missing: ${package_location}" 1;
                    fi
                    echo "${package_location}" >> "${TMP_PACKAGE_LIST_FILE}";
                    ;;

                # if a url then download to the source folder, without
                # clobbering existing file.
                # create path to the downloaded package in the source folder
                # and record it into the package list
                --package-url | -u)
                    wget \
                        --no-clobber \
                        --directory-prefix="${TMP_SOURCE_FOLDER}" \
                        "${package_location}" \
                    || abort "URL specified by ${package_type} could not be retrieved: ${package_location}" 1;

                    package_file="${TMP_SOURCE_FOLDER}/$(basename ${package_location})";
                    # record package entity
                    echo "${package_file}" >> "${TMP_PACKAGE_LIST_FILE}";
                    ;;

            esac;
        done;
    done;

    # if file does not exist then abort this should never happen, apparently
    if [ ! -e "${TMP_PACKAGE_LIST_FILE}" ]; then
        abort "No packages entries available to import" 1;
    fi

}


# ........................................................................... #
# generate default config for aptly using aptly, adjust the rootDir to proper
# pathing (aptly messes it up) and set the architecture
function create_aptly_config {

    local rootdir_lineno;
    local dot_aptly_conf_file;

    # note: since there is no option to config to specify where the config
    # should be generated and it always generates in $HOME/.aptly.conf
    # additionally, if $HOME/.aptly.conf does already exist stderr is poluted
    # with a message about creating .aptly.conf which presents an issue for
    # logging error. As such we will first create our own .aptly.conf with an
    # empty json object so it is read why 'aptly show' config is ran hence
    # preventing it from poluting stderr. Then we will redirect the output of
    # 'aptly show config' to our custom aptly.conf in TMP_APTLY_CONFIG_FILE.
    dot_aptly_conf_file="${TMP_APTLY_WORK_FOLDER}/.aptly.conf"
    echo "{}" > "${dot_aptly_conf_file}";
    HOME="${TMP_APTLY_WORK_FOLDER}" \
        aptly config show \
        1>"${TMP_APTLY_CONFIG_FILE}" \
    || abort "failed to generate \"aptly.conf\": ${TMP_APTLY_CONFIG_FILE}" 1;


    update_aptly_config_rootdir;
}


# ........................................................................... #
# update aptly.conf rootdir to point TMP_APTLY_ROOTDIR_FOLDER
function update_aptly_config_rootdir {
    # remove the dummy .aptly.conf
    rm \
        ${TMP_RM_VERBOSITY} \
        --force \
        "${dot_aptly_conf_file}" \
    || abort "failed to remove dummy \".aptly.conf\"" 1;

    cat "${TMP_APTLY_CONFIG_FILE}" \
    | jq \
        ".rootDir=\"${TMP_APTLY_ROOTDIR_FOLDER}\"" \
    > "${TMP_APTLY_CONFIG_FILE}.tmp" \
    || abort "failed to update aptly.conf \"rootDir\"" 1;

    mv \
        ${TMP_MV_VERBOSITY} \
        --force \
        "${TMP_APTLY_CONFIG_FILE}.tmp" \
        "${TMP_APTLY_CONFIG_FILE}";

}


# ........................................................................... #
# create repository with components, distribution using aptly
function create_new_repository {

    # aptly has no verbosity setting so we are forced to do redirects
    # setup verbosity redirects for stderr and stdout
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        # create 2 handles. 3 goes to stdout, 4 to stderr
        # this way verbosity is printed to their approper
        exec 3>&1;
    else
        exec 3>/dev/null;
    fi

    # create an aptly repository
    aptly \
        -config="${TMP_APTLY_CONFIG_FILE}" \
        repo create \
            -component="${TMP_OPTION_REPOSITORY_COMPONENT}" \
            -distribution="${TMP_OPTION_REPOSITORY_DISTRIBUTION}" \
            "${TMP_OPTION_REPOSITORY_NAME}" \
    1>&3 \
    || abort "failed to create debian repository" 1;

    # close out stdout and stderr verbosity file descriptors
    exec 3>&-;

}


# ........................................................................... #
# add debian packages from origin folder to the repository, replacing existing
# all packages
function import_debian_packages_into_repository {

    # aptly has no verbosity setting so we are forced to do redirects
    # setup verbosity redirects for stderr and stdout
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        # create 2 handles. 3 goes to stdout, 4 to stderr
        # this way verbosity is printed to their approper
        exec 3>&1;
    else
        exec 3>/dev/null;
    fi

    # go over package sources and add them to the aptly repository
    while read package_source; do
        log_verbose "package source ${package_source}";
        aptly \
            -config="${TMP_APTLY_CONFIG_FILE}" \
            repo add \
                "${TMP_OPTION_REPOSITORY_NAME}" \
                "${package_source}" \
        1>>"${TMP_APTLY_IMPORT_LOG}" \
        || abort_with_log \
             "${TMP_APTLY_IMPORT_LOG}" \
             "failed to import packages" 1;

        # cat the processing log out if successful and verbose is on
        if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
            cat "${TMP_APTLY_IMPORT_LOG}";
        fi

    done < "${TMP_PACKAGE_LIST_FILE}";

    # close out stdout and stderr verbosity file descriptors
    exec 3>&-;

}


# create a gpg keyring using our custome keyring  script with our custom config
# and homedir we will specify it to aptly using PATH. this is currently the
# only way to specify a custom gpg "binary" since aptly does not take it as
# parameter TODO: we should do a PR to aptly
function create_keyrings {

    local keyring_type;
    local keyring_file;
    local make_keyring_output_file;

    make_keyring_info_file="${TMP_OPTION_WORK_FOLDER}/keyring.info"

    "${TMP_SCRIPT_FOLDER}/artly-make-keyring.sh" \
      --output-folder "${TMP_GPG_HOMEDIR_FOLDER}" \
      --key-file "${TMP_SECRET_KEY_FILE}" \
      --gpg "${TMP_OPTION_GPG}" \
      --recreate \
      --quiet \
      --machine-readable \
    > "${make_keyring_info_file}" \
    || abort "failed to create a keyring from key file: ${TMP_SECRET_KEY_FILE}" 1;

    while read config_line; do
        # get the config key value and value
        config_key="$(echo ${config_line} | cut -d':' -f1)";
        config_value="$(echo ${config_line} | cut -d':' -f2)";
        # assign config values to their respective variables based on
        # config key
        case "$config_key" in
            keyring)
                TMP_KEYRING_FILE="${config_value}";
                ;;
            secret-keyring)
                TMP_SECRET_KEYRING_FILE="${config_value}";
                ;;
            imported-keyid)
                TMP_KEYID="${config_value}";
                ;;
        esac;
    done \
    < "${make_keyring_info_file}";
}


# ........................................................................... #
# create gpg.config file.
# force use of the keyring files and keyid we have
# set gpg.config permissions to 600
function create_gpg_config_file {

# in >=gpg2.1 specifying either or both primary-keyring and keyring in the
# config file has proven to a terrible idea.
#
# For some commands like --list-keys issued during "aptly repo publish" issued
# by aptly having both primary-keyring and keyring settings in the config
# causes gpg to exit with exit code 2 (GPG_ERR_UNKNOWN_PACKET)
#
# in another case, also during "aptly repo publish" signing of the Release file
# the --keyring argument is given to gpg by aptly it also cause gpg to exit
# with code 2 when either primary-keyring or keyring are specified in the
# config
#
#
# So far no good reason for this been found has been found
# only error message seen is:
# gpg: keyblock resource '<some path>/gpg_homedir/pubring.kbx': File exists
#
# As such we will avoid coding these setting in the config file until more
# information is forth comming and rely on sandboxing due to specification
# of --homedir and the fact that only one key is every imported into it
#
# Below are the settings that were used before:
#   no-default-keyring
#   primary-keyring ${TMP_KEYRING_FILE}
#   keyring ${TMP_KEYRING_FILE}
#   secret-keyring ${TMP_SECRET_KEYRING_FILE}
#
# Debug note, add before the gpg binary to see the gpg commands issued:
#   strace -f -s99999 -e trace=clone,execve

    cat >"${TMP_GPG_CONF_FILE}" <<EOF
default-key ${TMP_KEYID}
EOF

    # print out file if verbose
    cat_verbose "${TMP_GPG_CONF_FILE}";

    # change permission gor gpg.conf to the 600 for additional safety
    chmod \
        ${TMP_CHMOD_VERBOSITY} \
        600 \
        "${TMP_GPG_CONF_FILE}";

}


# ........................................................................... #
# create gpg executable to be used by apt publish repo on the PATH
# this script exists mostly because call to the gpg executable is hardcoded
# in aptly to 'gpg'. However currently aptly support for >=gpg 2.1 has some
# issues and not all distros us <gpg 2.1 we need to create a wrapper
# _CUSTOM_GPG_PATH passes in the unmodified PATH which is necessary to look up
# the 'gpg' executable by the same name without getting into an infinite loop
# which would be create if the wrapper which is also name 'gpg' is found on the
# PATH when it is run inside the wrapper.
function create_gpg_wrapper {

    cat >"${TMP_BIN_FOLDER}/gpg" <<EOF
#!/usr/bin/env bash

PATH="\${_CUSTOM_GPG_PATH}" \\
${TMP_OPTION_GPG} \\
    ${TMP_GPG_VERBOSITY} \\
    --options "${TMP_GPG_CONF_FILE}" \\
    --homedir "${TMP_GPG_HOMEDIR_FOLDER}" \\
    \${@};
EOF

    # make the script executable
    chmod \
        ${TMP_CHMOD_VERBOSITY} \
        u+x \
        "${TMP_BIN_FOLDER}/gpg";
}


# ........................................................................... #
# publish the repository, signing it with secret keyid from GPG_KEYID_FILE
# use our custom built gpg script
function publish_repository {

    local formated_architectures;

    # aptly has no verbosity setting so we are forced to do redirects
    # setup verbosity redirects for stderr and stdout
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        # create 2 handles. 3 goes to stdout, 4 to stderr
        # this way verbosity is printed to their approper
        exec 3>&1;
    else
        exec 3>/dev/null;
    fi

    # strip any extra whitespace after commans and quote all the architecures
    formated_architectures=$(\
        echo "${TMP_OPTION_REPOSITORY_ARCHITECTURES}" \
        | sed 's/ *//g' \
    );

    # run aptly publish using our gpg wrapper
    # for _CUSTOM_GPG_PATH explanation see create_gpg_wrapper
    _CUSTOM_GPG_PATH="${PATH}" \
    PATH="${TMP_BIN_FOLDER}:${PATH}" \
    aptly \
        -config="${TMP_APTLY_CONFIG_FILE}" \
        publish repo \
            -architectures="${formated_architectures}" \
            -keyring="${TMP_KEYRING_FILE}" \
            -secret-keyring="${TMP_SECRET_KEYRING_FILE}" \
            -gpg-key="${TMP_KEYID}" \
            -label="${TMP_OPTION_REPOSITORY_LABEL}" \
            -origin="${TMP_OPTION_REPOSITORY_ORIGIN}" \
            "${TMP_OPTION_REPOSITORY_NAME}" \
    1>&3 \
    || abort "failed to sign and publish the repository" 1;

    # if description is specified then go over Release and InRelease files
    # in the disttribution and replace the first instance of the "Description:"
    # with "Description:" + TMP_OPTION_REPOSITORY_DESCRIPTION
    if [ "${TMP_OPTION_REPOSITORY_DESCRIPTION}" != "" ]; then
        for release_file in "Release" "InRelease"; do
            sed \
                --in-place \
                "s/^Description:.*/Description: ${TMP_OPTION_REPOSITORY_DESCRIPTION}/" \
                "${TMP_APTLY_ROOTDIR_FOLDER}/public/dists/${TMP_OPTION_REPOSITORY_DISTRIBUTION}/${release_file}";
        done;
    fi

    # close out stdout and stderr verbosity file descriptors
    exec 3>&-;

    # get the count of imported pacakes and store it in
    # TMP_IMPORTED_PACKAGES_COUNT
    TMP_IMPORTED_PACKAGES_COUNT="$(get_repository_package_count)";

    # copy the "public" repository folder inside aptly rootdir to ubuntu folder
    # of the repository output folder

    cp \
        ${TMP_CP_VERBOSITY} \
        --recursive \
        "${TMP_APTLY_ROOTDIR_FOLDER}"/public \
        --no-target-directory \
        "${TMP_OPTION_OUTPUT_FOLDER}" \
    || abort "failed to copy repository to: ${TMP_OPTION_OUTPUT_FOLDER}" 1;

    log_unquiet "Copied repository to output folder: \
${TMP_OPTION_OUTPUT_FOLDER}";

}


# ........................................................................... #
# export public key to public.asc file in output folder
function export_public_key {

    local gpg_error_log;

    # setup verbosity redirects for stdout using a file descriptor
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        exec 3>&1;
    else
        exec 3>/dev/null;
    fi

    gpg_error_log="${TMP_OPTION_WORK_FOLDER}/gpg_error.log";

    # export armored public key using the keyid in the keyid file to
    # TMP_OPTION_PUBLIC_KEY_FILE. use --batch so it does not prompt, because it does.
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
        "${TMP_KEYID}"; #\
    1>&3 \
    2>"${gpg_error_log}" \
    || abort_with_log \
        "${gpg_error_log}" \
        "failed to export armored public key to ${TMP_PUBLIC_KEY_FILE}" 1;

    # check if public key file was actually created and if not abort
    if [ ! -f "${TMP_PUBLIC_KEY_FILE}" ]; then
        abort_with_log \
        "${gpg_error_log}" \
        "failed to export armored public key to ${TMP_PUBLIC_KEY_FILE}" 1;
    fi

}

# ........................................................................... #
# get count of imported packages
function get_repository_package_count {

    aptly \
        -config="${TMP_APTLY_CONFIG_FILE}" \
        repo show \
            "${TMP_OPTION_REPOSITORY_NAME}" \
    2>/dev/null \
    | grep "Number of packages: " \
    | cut \
        --delimiter ':' \
        --fields 2 \
    | cut \
        --characters 2;

}


# ........................................................................... #
# print out repository information
function print_repository_information {

    local keyring="${TMP_OPTION_OUTPUT_FOLDER}/";
    keyring="${keyring}$(basename ${TMP_KEYRING_FILE})"

    local secret_keyring="${TMP_OPTION_OUTPUT_FOLDER}/";
    secret_keyring="${secret_keyring}$(basename ${TMP_SECRET_KEYRING_FILE})";

    if [ ${TMP_OPTION_MACHINE_READABLE} -eq 1 ]; then
        echo "repository-name:${TMP_OPTION_REPOSITORY_NAME}";
        echo "repository-distribution:${TMP_OPTION_REPOSITORY_DISTRIBUTION}";
        echo "repository-component:${TMP_OPTION_REPOSITORY_COMPONENT}";
        echo "repository-architectures:${TMP_OPTION_REPOSITORY_ARCHITECTURES}";
        echo "repository-folder:${TMP_OPTION_OUTPUT_FOLDER}";
        echo "repository-label:${TMP_OPTION_REPOSITORY_LABEL}";
        echo "repository-origin:${TMP_OPTION_REPOSITORY_ORIGIN}";
        echo "repository-package-count:${TMP_IMPORTED_PACKAGES_COUNT}";
        echo "public-key:${TMP_PUBLIC_KEY_FILE}";
    else
        echo "Repository Name           : ${TMP_OPTION_REPOSITORY_NAME}";
        echo "Repository Distribution   : ${TMP_OPTION_REPOSITORY_DISTRIBUTION}";
        echo "Repository Component      : ${TMP_OPTION_REPOSITORY_COMPONENT}";
        echo "Repository Architectures  : ${TMP_OPTION_REPOSITORY_ARCHITECTURES}";
        echo "Repository Folder         : ${TMP_OPTION_OUTPUT_FOLDER}";
        echo "Repository Label          : ${TMP_OPTION_REPOSITORY_LABEL}";
        echo "Repository Origin         : ${TMP_OPTION_REPOSITORY_ORIGIN}";
        echo "GPG version               : $(gpg_version ${TMP_OPTION_GPG})";
        echo "Public Key                : ${TMP_PUBLIC_KEY_FILE}";
        echo "Repository Package Count  : ${TMP_IMPORTED_PACKAGES_COUNT}";
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
