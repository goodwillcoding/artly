#!/usr/bin/env bash

# ########################################################################### #
#
# Publish Debian repository to a Git repository
#
# ########################################################################### #

TMP_PROGRAM_VERSION="0.2";

# ........................................................................... #
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
# aptly script path
ARTLY_SCRIPT_PATH="${ARTLY_SCRIPT_PATH:-}";


# ........................................................................... #
# repository source folder
TMP_OPTION_SOURCE_FOLDER="";
# repository git uri
TMP_OPTION_REPOSITORY_GIT_URI="";
# commiter name
TMP_OPTION_COMMIT_AUTHOR="";
# commiter email
TMP_OPTION_COMMIT_EMAIL="";
# repository description to put in readme and the commit message
TMP_OPTION_COMMIT_MESSAGE="";
# work folder
TMP_OPTION_WORK_FOLDER="";
# machine readable output flag
TMP_OPTION_MACHINE_READABLE=0;

TMP_OPTION_VERBOSE=0;
TMP_OPTION_QUIET=0;
TMP_OPTION_NO_COLOR=0;
TMP_OPTION_DEBUG=0;
TMP_OPTION_VERSION=0;

# verbosity
TMP_RM_VERBOSITY="";
TMP_MKDIR_VERBOSITY="";
TMP_CP_VERBOSITY="";
# some git commands have --quiet flag and some do not
TMP_GIT_INIT_VERBOSITY="";
TMP_GIT_ADD_VERBOSITY="";
TMP_GIT_COMMIT_VERBOSITY="";
TMP_GIT_PUSH_VERBOSITY="";
# template for the work folder name
TMP_WORK_FOLDER_NAME_TEMPLATE="/tmp/artly-publish-git.XXXXXXXXXX";


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
${script_display_name} - Publish repository to Git repository.

Usage: ${script_display_name} [OPTIONS]

Publish Debian repository to a Git repository.

Can be used to push Deboan repositories documented with
\"document-debian-repository --style 'github-pages'\" to GitHub Pages. If doing
so on free GitHub.com account and not a private installation please read the
disclaime included with Artly as well GitHub.com terms of usage.

IMPORTANT:
   Git operations performed by this script is a DESTRUCTIVE operation that uses
   'git push --force' and wipes out the existing content of git repository and
   all of it's history.

Options:

    -s, --source-folder <path>
        Source folder containing the repository to publush

    -u, --git-uri <uri>
        Git repository the debian repository is pushed to.
        (Example: git@github.com:myuser/my-debian-repository.git)

    -a, --author
        Commit author.

    -e, --email
        Commit author's email.

    -m, --message
        Commit message.

    --machine-readable
        Optional, print out colon separated output. This only prints out
        repository information.

    --work-folder <path>
        Optional, work folder path, needed to generate the repository. By
        default the work folder name is created by mktemp using following
        template \"${TMP_WORK_FOLDER_NAME_TEMPLATE}\".

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


# ........................................................................... #
# clear all (ERR EXIT INT TERM) error traps
function clear_error_traps {
    # clear all traps so we do not hit recusions
    trap - ERR EXIT INT TERM;
}



# ........................................................................... #
# main entry point, checks commands and processes arguments and commands
# no traps here, since we do not need arror reporting
# :{1}: command or option to run
function begin {

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

    # preparate repository in the work folder
    create_and_configure_working_git_repository;

    # push the repository upstream
    push_repository_upstream;

    # if not debugging remove the work folder
    if [ ${TMP_OPTION_DEBUG} -eq 0 ]; then
        remove_work_folder;
    fi

    # print repository information
    print_repository_information;

}


# ........................................................................... #
# checks for all the commands required for setup and activate
# this does not include the python commands we install
function check_commands {

    # check for bash 4
    cmd_exists_bash4_or_abort;

    # check gnu getop
    cmd_exists_gnu_getopt_or_abort;

    # check for a whole set of commands
    cmds_exists_or_abort \
        "echo" "basename" "dirname" "mkdir" "rm" "rev" "cut" "grep" \
        "sed" "git";

}


# ........................................................................... #
# get script params and store them
function process_script_arguments {
    local short_args;
    local long_args="";
    local processed_args;

    short_args="s: u: n: a: e: m: v q h";
    long_args+="source-folder: git-uri: name: author: email: message: ";
    long_args+="machine-readable work-folder: verbose quiet debug version";
    long_args+="help";


    # if no arguments given print usage
    if [ $# -eq 0 ]; then
        # print usage to stderr since no valid command was provided
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
            --source-folder | -s)
                TMP_OPTION_SOURCE_FOLDER="${2}";
                shift;
                ;;

            # store git uri
            --git-uri | -u)
                TMP_OPTION_REPOSITORY_GIT_URI="${2}";
                shift;
                ;;

            # store commit author
            --author | -a)
                TMP_OPTION_COMMIT_AUTHOR="${2}";
                shift;
                ;;

            # store commit author email
            --email | -e)
                TMP_OPTION_COMMIT_EMAIL="${2}";
                shift;
                ;;

            # store commit message
            --message | -m)
                TMP_OPTION_COMMIT_MESSAGE="${2}";
                shift;
                ;;

            # store machine readable flag
            --machine-readable)
                TMP_OPTION_MACHINE_READABLE=1;
                ;;

            # store work folder path
            --work-folder)
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
                clear_error_traps;
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
                echo "Unknown argument(s) given: ${1}">&2;
                exit 2;
                ;;

            *)
                # print usage to stderr since no valid command was provided
                clear_error_traps;
                usage 1>&2;
                echo "No arguments given.">&2;
                exit 2;
                ;;
        esac
        shift;
    done


}


# ........................................................................... #
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


# ........................................................................... #
# print out version
function print_version {

    local artly_arguments;

    if [ "${TMP_OPTION_MACHINE_READABLE}" -eq 1 ]; then
        echo "artly-publish-git-version:${TMP_PROGRAM_VERSION}";
        artly_arguments="--machine-readable";
    else
        echo "Artly Publish Git version: ${TMP_PROGRAM_VERSION}";
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

    # check if source folder is specified, if not abort with message
    if [ "${TMP_OPTION_SOURCE_FOLDER}" == "" ]; then
        abort "Please specify output folder using --source-folder/-s" 1;
    fi

    # check if source folder is specified, if not abort with message
    if [ "${TMP_OPTION_REPOSITORY_GIT_URI}" == "" ]; then
        abort "Please specify a Git URI --git-uri-folder/-u" 1;
    fi

    # check if repository name is specified, if not abort with message
    if [ "${TMP_OPTION_COMMIT_AUTHOR}" == "" ]; then
        abort "Please specify commit author using --author/-a" 1;
    fi

    # check if repository name is specified, if not abort with message
    if [ "${TMP_OPTION_COMMIT_EMAIL}" == "" ]; then
        abort "Please specify commit email using --email/-e" 1;
    fi

    # check if commit message is specified, if not abort with message
    if [ "${TMP_OPTION_COMMIT_MESSAGE}" == "" ]; then
        abort "Please specify commit message using --message/-m" 1;
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

    # if debug then turn on verbosity
    if [ ${TMP_OPTION_DEBUG} -eq 1 ]; then
        TMP_OPTION_VERBOSE=1;
    fi

    # if verbose the set gpg, rm, mkdir verbosity
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        TMP_RM_VERBOSITY="--verbose";
        TMP_MKDIR_VERBOSITY="--verbose";
        TMP_CP_VERBOSITY="--verbose";
        TMP_GIT_INIT_VERBOSITY="";
        TMP_GIT_ADD_VERBOSITY="--verbose";
        TMP_GIT_COMMIT_VERBOSITY="--verbose";
        TMP_GIT_PUSH_VERBOSITY="--verbose";
    else
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
        TMP_CP_VERBOSITY="";
        TMP_GIT_INIT_VERBOSITY="--quiet";
        TMP_GIT_ADD_VERBOSITY="";
        TMP_GIT_COMMIT_VERBOSITY="--quiet";
        TMP_GIT_PUSH_VERBOSITY="";
    fi

    # if quiet, set verbosity to 0 and enforce the quietest options for
    # those utilities that have it (gpg, rm, mkdir, mv, chmod)
    if [ ${TMP_OPTION_QUIET} -eq 1 ]; then
        TMP_OPTION_VERBOSE=0;
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
        TMP_CP_VERBOSITY="";
        TMP_GIT_INIT_VERBOSITY="--quiet";
        TMP_GIT_ADD_VERBOSITY="";
        TMP_GIT_COMMIT_VERBOSITY="--quiet";
        TMP_GIT_PUSH_VERBOSITY="--quiet";
    fi

    # repository readme file location
    # even though we are creating html when creating the readme
    # we are placing it in an .md file because README.html are not
    # supported by markdown files support basic html tag
    TMP_REPOSITORY_README_FILE="${TMP_OPTION_WORK_FOLDER}/README.md";

}


# ........................................................................... #
# log paths and various scripts information
function log_script_info {

    log_verbose "Repository Source Folder  : ${TMP_OPTION_SOURCE_FOLDER}";
    log_verbose "Repository Git URI        : ${TMP_OPTION_REPOSITORY_GIT_URI}";
    log_verbose "Commit Author             : ${TMP_OPTION_COMMIT_AUTHOR}";
    log_verbose "Commit Email              : ${TMP_OPTION_COMMIT_EMAIL}";
    log_verbose "Work folder               : ${TMP_OPTION_WORK_FOLDER}";
    log_verbose "Debug                     : $(humanize_bool ${TMP_OPTION_DEBUG})";

}

# ........................................................................... #
# create output, work, homedir folder removing them if needed
# also homedir folder permissions are set at 700
function create_folders {

    # remove work folder if exists, forcing removal if recreate flag is set
    remove_work_folder;
    # create work folder
    mkdir \
        ${TMP_MKDIR_VERBOSITY} \
        --parent \
        "${TMP_OPTION_WORK_FOLDER}";
    log_unquiet "Created work folder: ${TMP_OPTION_WORK_FOLDER}";

}


# ........................................................................... #
# Remove work folder if it is exists
function remove_work_folder {

    # remove the work for this script folder if exist
    if [ -d "${TMP_OPTION_WORK_FOLDER}" ]; then
        # use --force since git has protected files
        # maybe
        rm \
            ${TMP_RM_VERBOSITY} \
            --force \
            --recursive \
            "${TMP_OPTION_WORK_FOLDER}";
        log_unquiet "Removed work folder: \
${TMP_OPTION_WORK_FOLDER}";

    fi

}


# ........................................................................... #
# remove all the temporary folders and files if debug is that
# this removes output and work folder
function remove_temporary_directories_and_files {

    # if debug is NOT set "force" remove output and work folder
    if [ ${TMP_OPTION_DEBUG} -eq 0 ]; then
        remove_work_folder;
    fi

}


# ........................................................................... #
function create_and_configure_working_git_repository {

    # copy the repository over the working folder
    cp \
        ${TMP_CP_VERBOSITY} \
        --recursive \
        --no-target-directory \
        "${TMP_OPTION_SOURCE_FOLDER}" \
        "${TMP_OPTION_WORK_FOLDER}";


    # clean it up of any git repository artifacts
    rm \
        ${TMP_RM_VERBOSITY} \
        --recursive \
        --force \
        "${TMP_OPTION_WORK_FOLDER}/.git";

    # create a new repository
    # note: git init has no verbose
    git \
        init \
        ${TMP_GIT_INIT_VERBOSITY} \
            "${TMP_OPTION_WORK_FOLDER}";

    # configure committer author
    # note: git config has no verbose
    # this git command has no verbosity setting at all
    git \
       --git-dir "${TMP_OPTION_WORK_FOLDER}/.git" \
       --work-tree "${TMP_OPTION_WORK_FOLDER}" \
        config \
            user.name \
            "${TMP_OPTION_COMMIT_AUTHOR}";

    # configure committer author
    # note: git config has no verbose
    # this git command has no verbosity setting at all
    git \
       --git-dir "${TMP_OPTION_WORK_FOLDER}/.git" \
       --work-tree "${TMP_OPTION_WORK_FOLDER}" \
        config \
            user.email \
            "${TMP_OPTION_COMMIT_EMAIL}";

    # add the git uri as remote origin
    # this git command has no verbosity setting for "remote add"
    git \
       --git-dir "${TMP_OPTION_WORK_FOLDER}/.git" \
       --work-tree "${TMP_OPTION_WORK_FOLDER}" \
        remote \
            add \
                origin \
                "${TMP_OPTION_REPOSITORY_GIT_URI}";

}


# ........................................................................... #
# push the repositoty to git upstream
function push_repository_upstream {

    local commit_date;

    # add all files in the folder to the commit
    git \
       --git-dir "${TMP_OPTION_WORK_FOLDER}/.git" \
       --work-tree "${TMP_OPTION_WORK_FOLDER}" \
        add \
            ${TMP_GIT_ADD_VERBOSITY} \
            --all;

    # get commit date in UTC
    commit_date=$(date +"%Y-%m-%d %R %Z %z");
    # commit to the local git repository with UTC dated commit message
    git \
       --git-dir "${TMP_OPTION_WORK_FOLDER}/.git" \
       --work-tree "${TMP_OPTION_WORK_FOLDER}" \
        commit \
            ${TMP_GIT_COMMIT_VERBOSITY} \
            --all \
            --message "${TMP_OPTION_COMMIT_MESSAGE} published on \
${commit_date}";

    # force push to the repository so we override it
    log_unquiet "Force pushing to master branch of repository: \
${TMP_OPTION_REPOSITORY_GIT_URI}";
    git \
       --git-dir "${TMP_OPTION_WORK_FOLDER}/.git" \
       --work-tree "${TMP_OPTION_WORK_FOLDER}" \
        push \
            ${TMP_GIT_PUSH_VERBOSITY} \
            --force \
            --set-upstream \
            origin \
            master;

}


# ........................................................................... #
# print out repository information
function print_repository_information {

    if [ ${TMP_OPTION_MACHINE_READABLE} -eq 1 ]; then
        echo "repository-git-uri:${TMP_OPTION_REPOSITORY_GIT_URI}";
        echo "repository-commit-author:${TMP_OPTION_COMMIT_AUTHOR}";
        echo "repository-commit-email:${TMP_OPTION_COMMIT_EMAIL}";
        echo "repository-commit-message:${TMP_OPTION_COMMIT_MESSAGE}";
    else
        log_unquiet "Repository Git URI        :  ${TMP_OPTION_REPOSITORY_GIT_URI}";
        log_unquiet "Repository Commit Author  :  ${TMP_OPTION_COMMIT_AUTHOR}";
        log_unquiet "Repository Commit Email   :  ${TMP_OPTION_COMMIT_EMAIL}";
        log_unquiet "Repository Commit Message :  ${TMP_OPTION_COMMIT_MESSAGE}";
    fi

}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ #
# import utils.sh
if [ -f "${TMP_SCRIPT_FOLDER}/utils.sh" ]; then
    source "${TMP_SCRIPT_FOLDER}/utils.sh"
else
    echo "
Could not load required '${TMP_SCRIPT_FOLDER}/utils.sh' module.

" >&2;
    exit 1;
fi


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ #
begin "$@";
