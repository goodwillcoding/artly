#!/usr/bin/env bash

# ########################################################################### #
#
# Document the debian repository with README instructions and directory HTML
# indexes.
#
# ########################################################################### #

# TODO: add argument for specifying keyserver/keyid


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
# output folder
TMP_OPTION_OUTPUT_FOLDER="";
# repository source folder
TMP_OPTION_SOURCE_FOLDER="";
# repository name to be used in the apt source file name
TMP_OPTION_REPOSITORY_NAME="";
# repository description to put in readme and the commit message
TMP_OPTION_REPOSITORY_TITLE="";
# location of the repository to put in the readme
TMP_OPTION_REPOSITORY_URL="";
# location of public key to put in the readme
TMP_OPTION_REPOSITORY_PUBLIC_KEY_URL="";
# keyservers/keys
TMP_OPTION_REPOSITORY_PUBLIC_KEY_SERVER_KEY="";
# repository packages to install to put in the readme
TMP_OPTION_REPOSITORY_PACKAGE="";
# style for repository documentation (html, github-pages, etc)
TMP_OPTION_STYLE="";
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
TMP_RM_VERBOSITY="";
TMP_MKDIR_VERBOSITY="";
TMP_CP_VERBOSITY="";

# template for the work folder name
TMP_WORK_FOLDER_NAME_TEMPLATE="/tmp/artly-document-debian-repository.XXXXXXXXXX";
# work repository folder
TMP_WORK_REPOSITORY_FOLDER="";

# the temporary readme file content of which will be embedded into the index
TMP_INDEX_EMBEDDED_README_FILE="";

# static assets used in html generation (css files and so on)
TMP_STATIC_ASSETS_FOLDER="${TMP_SCRIPT_FOLDER}/_static";

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
${script_display_name} - generate Debian repository with READMEs containing
repository setup instructions as well as HTML directory indexes for browsing.

Usage: ${script_display_name} [OPTIONS]

Make the Debian repository human friendly by generating READMEs with repository
with repository setup instructions and HTML directory index so it can be
browsed.

Options:

    -o, --output-folder <path>
        Output folder for the generated repository.

    -s, --source-folder <path>
        Source folder containing the repository.

    -n, --name
        Repository name.
        Used as to create the file name for the APT configuration file.

        Note: Should not contain any '/' and suggested it is kept short, does
        not use spaces and be descriptive of the repository.

        APT configuration file form is: <repository name>-<distribution>.list

    -t, --title
        Repository title.
        Used as repository title in APT configuration file.

    -u, ,--url
        Repository DEB/APT URL.
        Used as APT source in the APT configuration file.

    -k, --public-key-url
        Semi-optional, URL to the public key the repository is signed with.

        Note: at least 1 public-key-url or 1 key-server-keyid should specified.

    -K, --key-server-keyid
        Semi-optional, keyserver and keyid key the repository is signed with.

        Multiple keyservers:keyids can be specified, with parameter quoted
        keyserver:keyid pair single space separated.
        (Example: -K \"keys.gnupg.net:8507EFB5 keyserver.ubuntu.com:8507EFA5\")

        Note: at least 1 public-key-url or 1 key-server-keyid should specified.

    -p, --package
        Optional, package available to the user to install.
        Multiple packages can be specified, with parameter quoted and packages
        single space separated. (Example: --packages \"python2.7 ncdu mc\")

    -S, --style
        Optional, Style the README and the html for specific publishing target
        Allowed values are: 'html', 'github-pages'. Default to 'html'.

        For 'github-pages' the readme file will be README.md since that is
        the only format GitHub supports for HTML files that displayed in
        as a readme as part of the repository. Also, add a note that
        GitHub Pages does support viewing of the files because of unsupported
        mime-types.

    --recreate
        Optional, delete previous output folder by the same name before
        creating it again. Useful when you want to recreate the keys without
        having to do manual removal.

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

    -h, --help
        show help for this script.
";

# TODO: keep machine readable here for now while we determine what's needed
    # --machine-readable
    #     Optional, print out colon separated output. This only prints out
    #     repository information.


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

    # copy the repository over to the work folder
    copy_repository_to_repository_work_folder;

    # create a readme that will go into the index.html-s and body of readme
    create_embedded_readme_file;

    # create the real readme
    create_readme_file;

    # generate html indexes
    generate_html_index_files;

    # add files specific to the requested style
    add_style_specific_stylings;

    # copy static assets to top level of the output folder
    copy_static_assets;

    # push the repository upstream
    copy_repository_to_output_folder;

    # if not debugging remove the work folder
    if [ ${TMP_OPTION_DEBUG} -eq 0 ]; then
        remove_work_folder;
    fi

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
        "find" "sed";

}


# ........................................................................... #
# get script params and store them
function process_script_arguments {
    local short_args;
    local long_args="";
    local processed_args;

    short_args="o: s: h: a: e: n: t: u: k: K: p: S: v q h";
    long_args+="output-folder: source-folder: name: title: url: ";
    long_args+="public-key-url: key-server-keyid: package: style: recreate ";
    long_args+="machine-readable  work-folder: verbose quiet debug help";

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
            --output-folder | -i)
                TMP_OPTION_OUTPUT_FOLDER="${2}";
                shift;
                ;;

            # store source folder path
            --source-folder | -s)
                TMP_OPTION_SOURCE_FOLDER="${2}";
                shift;
                ;;

            # store repository name for the readme
            --name | -n)
                TMP_OPTION_REPOSITORY_NAME="${2}";
                shift;
                ;;

            # store repository title for the readme
            --title | -t)
                TMP_OPTION_REPOSITORY_TITLE="${2}";
                shift;
                ;;

            # store repository url for the reamme
            --url | -u)
                TMP_OPTION_REPOSITORY_URL="${2}";
                shift;
                ;;

            # store repository public key for the readme
            --public-key-url | -k)
                TMP_OPTION_REPOSITORY_PUBLIC_KEY_URL="${2}";
                shift;
                ;;

            # store repository keyserver public key for the readme
            --key-server-keyid | -K)
                TMP_OPTION_REPOSITORY_PUBLIC_KEY_SERVER_KEY="${2}";
                shift;
                ;;

            # store repository packages to install for the readme
            --package | -p)
                TMP_OPTION_REPOSITORY_PACKAGE="${2}";
                shift;
                ;;

            # store repository public key for the readme
            --style | -S)
                TMP_OPTION_STYLE="${2}";
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

    local key_pair;
    local keyserver_keyid_check;

    # output folder for the keys
    if [ "${TMP_OPTION_OUTPUT_FOLDER}" == "" ]; then
        abort "Please specify  output folder using --output-folder/-o" 1;
    fi

    # check if source folder is specified, if not abort with message
    if [ "${TMP_OPTION_SOURCE_FOLDER}" == "" ]; then
        abort "Please specify output folder using --source-folder/-s" 1;
    fi

    # check if repository name is specified, if not abort with message
    if [ "${TMP_OPTION_REPOSITORY_NAME}" == "" ]; then
        abort "Please specify repository name using --name/-n" 1;
    fi

    # check if repository title is specified, if not abort with message
    if [ "${TMP_OPTION_REPOSITORY_TITLE}" == "" ]; then
        abort "Please specify repository title using --title/-t" 1;
    fi

    # check if repository url is specified, if not abort with message
    if [ "${TMP_OPTION_REPOSITORY_URL}" == "" ]; then
        abort "Please specify repository url using --url/-u" 1;
    fi

    # check if public key url is specified, if not abort with message
    if    [ "${TMP_OPTION_REPOSITORY_PUBLIC_KEY_URL}" == "" ] \
       && [ "${TMP_OPTION_REPOSITORY_PUBLIC_KEY_SERVER_KEY}" == "" ]; then
        abort "Please specify either a public key URL using \
--public-key-url/-k or a keyserver and keyid using --key-server-keyid/-K" 1;
    fi

    # if keyserver keyid is specified, check if the keyserver:keyid has
    # only 1 ':' and if not abort
    if [ "${TMP_OPTION_REPOSITORY_PUBLIC_KEY_SERVER_KEY}" != "" ]; then
        for key_pair in ${TMP_OPTION_REPOSITORY_PUBLIC_KEY_SERVER_KEY}; do
            keyserver_keyid_check=$(\
                echo "${key_pair}" \
                | ( grep -o ':' 2>/dev/null  || true ) \
                | wc -l);
            if [ ${keyserver_keyid_check} -ne 1 ]; then
                abort "Please specify a valid keyserver:keyid pair using for \
--key-server-keyid/-K" 1;
            fi
        done
    fi


    # check if style is specified check that it is either 'html' or
    # 'github-pages'. Default to 'html' if non specified
    if [ "${TMP_OPTION_STYLE}" == "" ]; then
        TMP_OPTION_STYLE="html";
    else
        if    [ "${TMP_OPTION_STYLE}" != "html" ] \
           && [ "${TMP_OPTION_STYLE}" != "github-pages" ]; then
            abort "Allowed --style/-s values are 'html', 'github-pages'" 1;
        fi
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
    else
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
        TMP_CP_VERBOSITY="";
    fi

    # if quiet, set verbosity to 0 and enforce the quietest options for
    # those utilities that have it (gpg, rm, mkdir, mv, chmod)
    if [ ${TMP_OPTION_QUIET} -eq 1 ]; then
        TMP_OPTION_VERBOSE=0;
        TMP_RM_VERBOSITY="";
        TMP_MKDIR_VERBOSITY="";
        TMP_CP_VERBOSITY="";
    fi

    # set the work repository folder
    TMP_WORK_REPOSITORY_FOLDER="${TMP_OPTION_WORK_FOLDER}/repository";
    # set embedded readme file path
    TMP_INDEX_EMBEDDED_README_FILE="${TMP_OPTION_WORK_FOLDER}/embedded_readme.html";

}


# ........................................................................... #
# log paths and various scripts information
function log_script_info {

    log_verbose "Output Folder             : ${TMP_OPTION_SOURCE_FOLDER}";
    log_verbose "Repository Source Folder  : ${TMP_OPTION_SOURCE_FOLDER}";
    log_verbose "Repository Name           : ${TMP_OPTION_REPOSITORY_NAME}";
    log_verbose "Repository Title          : ${TMP_OPTION_REPOSITORY_TITLE}";
    log_verbose "Repository URL            : ${TMP_OPTION_REPOSITORY_URL}";
    log_verbose "Repository Public Key URL : ${TMP_OPTION_REPOSITORY_PUBLIC_KEY_URL}";
    log_verbose "Work folder               : ${TMP_OPTION_WORK_FOLDER}";
    log_verbose "Recreate                  : $(humanize_bool ${TMP_OPTION_RECREATE})";
    log_verbose "Debug                     : $(humanize_bool ${TMP_OPTION_DEBUG})";

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
        rm \
            ${TMP_RM_VERBOSITY} \
            --recursive \
            "${TMP_OPTION_WORK_FOLDER}";
        log_unquiet "Removed work folder: ${TMP_OPTION_WORK_FOLDER}";
    fi

}


# ........................................................................... #
# copy the repository over the working folder
function copy_repository_to_repository_work_folder {

    cp \
        ${TMP_CP_VERBOSITY} \
        --recursive \
        "${TMP_OPTION_SOURCE_FOLDER}" \
        --no-target-directory \
        "${TMP_WORK_REPOSITORY_FOLDER}";
}


# ........................................................................... #
# create an html readme that will be embedded ito the index.html and the body
# of the readme file
function create_embedded_readme_file {

    # TODO: unset the arrays in the end of the function since they are global?
    declare -a distributions;
    declare -a components;
    local distribution;
    declare -a key_import_methods;
    local key_pair;
    local key_server;
    local key_id;
    local package_name;

    readarray -t distributions < <(\
        find \
            "${TMP_OPTION_SOURCE_FOLDER}/dists/"* \
            -maxdepth 0 \
            -type d \
            -exec basename '{}' \;)

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # generate html for repository title, repository location and start the
    # "adding repository to your system" section
    cat <<____EOF > ${TMP_INDEX_EMBEDDED_README_FILE}
<h1>
  ${TMP_OPTION_REPOSITORY_TITLE}
</h1>
<h3>
  Location
</h3>
<ul>
  <li>
    <a href="${TMP_OPTION_REPOSITORY_URL}">${TMP_OPTION_REPOSITORY_URL}</a>
  </li>
</ul>
<h3>
  Supported Distributions
</h3>
<ul>
____EOF

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # add all sipposed distributions
    # also, capitalize the distribution name for humans
    for distribution in "${distributions[@]}"; do
        cat <<________EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
  <li>
    ${distribution^}
  </li>
________EOF
    done;

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # add Launch terminal and Find out your distrubution instructions
    cat <<____EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
</ul>

<h3>
  Adding this repository as an APT source
</h3>
<ol>
  <li>
    Launch your terminal application (Terminal, Console, iTerm2, etc...)
    <blockquote>
      ...
    </blockquote>
  </li>
  <li>
    Find out youy distribution by running the following command in your
    terminal.
    <blockquote>
      <pre>lsb_release --short --codename</pre>
      You will see your distribution (for example, on my system it shows
      <strong>xenial</strong>):
      <blockquote><pre>xenial</pre></blockquote>
    </blockquote>
  </li>
  <li>
    <p>
      Add the repository for your distribution (from the last command) to your
      APT sources by running the following command in your terminal.
    </p>
____EOF

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # add instructions for each distribution
    cat <<____EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
    <blockquote>
    <div class='panel panel-default'>
____EOF

    for distribution in "${distributions[@]}"; do
        # read the componets for each distrubution into the components array
        readarray -t components < <(\
            find \
                "${TMP_OPTION_SOURCE_FOLDER}/dists/${distribution}"/* \
                -maxdepth 0 \
                -type d \
                -exec basename '{}' \;)

        # capitalize the distribution name for humans
        cat <<________EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
      <div class="panel-heading">
        For the <strong>${distribution^}</strong> distribution run:
      </div>
      <div class="panel-body">
        <pre>echo "deb ${TMP_OPTION_REPOSITORY_URL} ${distribution} ${components[@]} #${TMP_OPTION_REPOSITORY_TITLE}" \\
| sudo tee --append /etc/apt/sources.d/${TMP_OPTION_REPOSITORY_NAME}-${distribution}.list</pre>
      </div>
________EOF
    done;
    cat <<____EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
    </div>
    </blockquote>
____EOF

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # generate html for adding public key and updating refresning local
    # repository indexes

    # count the methods so we know to include instruction for choosing a
    # specific methods
    read -a key_import_methods \
        <<<"${TMP_OPTION_REPOSITORY_PUBLIC_KEY_URL} ${TMP_OPTION_REPOSITORY_PUBLIC_KEY_SERVER_KEY}";

    cat <<____EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
  </li>
  <li>
    <p>
      Import the ${TMP_OPTION_REPOSITORY_TITLE} <strong>Public GPG key</strong>
      (which was used to sign with repository) by running the following command
      in your terminal.
____EOF

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # if multiple methods to install keys tell the user to use any one of them
    if [ ${#key_import_methods[@]} -gt 1 ]; then
        cat <<________EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
      <br />
      <strong>
        Note: multiple methods of key import are provided to for your convience
        and security. You can pick any of them and if they do not work,
        try another.
      </strong>
    </p>
    <blockquote>
________EOF
    else
        cat <<________EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
    </p>
    <blockquote>
________EOF
    fi

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # generate html for public key url via wget (if given)
    if [ "${TMP_OPTION_REPOSITORY_PUBLIC_KEY_URL}" != "" ]; then
        cat <<________EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
      <pre>wget --quiet ${TMP_OPTION_REPOSITORY_PUBLIC_KEY_URL} --output-document - \\
| sudo apt-key add -</pre>
________EOF
    fi

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # generate html for each key server (if given)
    if [ "${TMP_OPTION_REPOSITORY_PUBLIC_KEY_SERVER_KEY}" != "" ]; then
        # go over each keyserver:keyid and create an 'apt-key adv' for it
        for key_pair in ${TMP_OPTION_REPOSITORY_PUBLIC_KEY_SERVER_KEY}; do
            # get keyserver and keyid
            key_server=$(echo "${key_pair}" | cut -d':' -f1)
            key_id=$(echo "${key_pair}" | cut -d':' -f2)
            cat <<-____________EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
      <pre>sudo apt-key adv --keyserver ${key_server} --recv-keys ${key_id}</pre>
____________EOF
        done
    fi
    cat <<____EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
    </blockquote>
  </li>
  <li>
    <p>
      Now refresh your local repository index by running the following command
      in your terminal.
    </p>
    <blockquote>
        <pre>sudo apt-get update</pre>
    </blockquote>
  </li>
  <li>
    <p>
      The packages from this repository should now be available for
      installation. You can install any of them by running following command(s)
      in your terminal.
    </p>
    <blockquote>
____EOF

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # if no packages specified add generic apt-install <some package>
    if [ "${TMP_OPTION_REPOSITORY_PACKAGE}" == "" ]; then
        cat <<________EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
      <pre>sudo apt-get install <some-package></pre>
________EOF
    else
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
        # if packages are given the add instructions for installing each
        # go over each package and create an 'apt-get install' for it
        for package_name in ${TMP_OPTION_REPOSITORY_PACKAGE}; do
            cat <<-____________EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
      To install <strong>${package_name}</strong> package run:
      <pre>sudo apt-get install ${package_name}</pre>
____________EOF
        done
    fi
    cat <<-____EOF >> ${TMP_INDEX_EMBEDDED_README_FILE}
    </blockquote>
  </li>
</ol>
____EOF


}


# ........................................................................... #
# create an html readme file itself
function create_readme_file {

    # for both html and github-pages create an html readme
    _html_document_beginning_to_file \
        "${TMP_WORK_REPOSITORY_FOLDER}/README.html" \
        "." \
        "${TMP_OPTION_REPOSITORY_TITLE}";
    # embed the embedded readme
    cat "${TMP_INDEX_EMBEDDED_README_FILE}" >> \
        "${TMP_WORK_REPOSITORY_FOLDER}/README.html";
    # close html document
    _html_document_ending_to_file \
        "${TMP_WORK_REPOSITORY_FOLDER}/README.html";

}


# ........................................................................... #
# generate html index files
function generate_html_index_files {

    # path part of the URL for the repository, used for display of directory
    # traversal
    local display_base_folder;
    local full_path_repository_folder;
    local full_path_current_folder;
    local display_current_folder;
    declare -a repository_files;

    # extract the base path of the URL
    # just in case this strips off everything after the ? and # since
    # the current belief is that this is a folder
    # strip any trailing backslaches
    # prefix this with a slash so it so it matches the URI spec
    display_base_folder=/$(\
        echo "${TMP_OPTION_REPOSITORY_URL}" \
        | cut -d'/' -f4- \
        | cut -d'?' -f1 \
        | cut -d'#' -f1 \
        | sed "s/\/*$//"
    )

    # get full path to the source folder, so we can use it later
    # to generate path relative to the source folder
    full_path_repository_folder="$(cd ${TMP_WORK_REPOSITORY_FOLDER}; pwd)"

    # go over all folders but ignoring any that start with ".""
    readarray -t repository_files < <(\
        find \
            "${TMP_WORK_REPOSITORY_FOLDER}" \
            -not -path '*/\.*' \
            -type d)

    for current_folder in "${repository_files[@]}"; do
        # get full path of the current folder
        full_path_current_folder=$(cd "${current_folder}"; pwd)
        # now get the display path of the current folder by removing the
        # full path of the work folder from it
        display_current_folder="${full_path_current_folder:${#full_path_repository_folder}}";

        # generate index html for the current_folder
        # pass the display top folder
        _create_index_html \
            "${current_folder}"\
            "${display_current_folder}" \
            "${display_base_folder}";
    done;

}


# ........................................................................... #
function _create_index_html {

    # path to current folder, which includes the source folder path
    # example /tmp/artly-document-debian-repository.A5FPPMZ33F/dist/xenial
    local current_folder;
    # path to the display version of the current folder relative to the source
    # path. Going off the examle for current folder this would be:
    # /dist/xenial
    # to note for the most top level folder this is empty "" (does not start)
    # with a slash
    # TODO: maybe fix that
    local display_current_folder;
    local display_base_folder;
    local item_name;

    local index_html_file;
    local parent_directory_html;
    local title_html;
    local directory_header;

    local relative_base_folder;
    local base_folder_depth;

    declare -a filesystem_items;
    local filesystem_item;
    local filesystem_item_date;
    local filesystem_item_size;
    local filesystem_item_icon;
    local link_url;

    # get the first parameter
    current_folder="${1}";
    display_current_folder="${2}";
    display_base_folder="${3}"

    # create path for index.html we are generating
    index_html_file="${current_folder}/index.html";

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # generate parent directory link, title and directory listing header for
    # use later
    # if we are at the top folder we do not need a parent links
    # if we are at the top folder we also do not need the folder
    # additionally the title for the top level folder does not need the
    # "contents of" verbiage
    if [ "${display_current_folder}" != "" ]; then
        parent_directory_html="    <tr><td colspan="3">[ <a href=../>Parent Directory</a> ]</td></tr>";
        title_html="${TMP_OPTION_REPOSITORY_TITLE}: contents of ${display_current_folder}";
        directory_header="Contents of ${display_base_folder}${display_current_folder}"
    else
        parent_directory_html="";
        title_html="${TMP_OPTION_REPOSITORY_TITLE}";
        directory_header="Contents of ${display_base_folder}"
    fi

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # generate the relative path to the top of the folder from the given
    # filename this is used to load css using a relative path
    # basically if the index.html path is /foo/bar/index.html the relative
    # path will be be "../../" . also, for the top level return "./"
    # use true to supress error message from grep if we find nothing, allowing
    # wc -l to processed and hence returing 0
    base_folder_depth=$(\
        echo "${display_current_folder}" \
        | ( grep -o '/' 2>/dev/null  || true ) \
        | wc -l);
    if [ ${base_folder_depth} -eq 0 ]; then
        relative_base_folder=".";
    else
        relative_base_folder=$(printf '%0.s../' $(seq 1 ${base_folder_depth}));
        # strip the trailing '/'
        relative_base_folder="${relative_base_folder::-1}"
    fi

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # start the index.html, give it title
    _html_document_beginning_to_file \
        "${index_html_file}" \
        "${relative_base_folder}" \
        "${title_html}";

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # if we are at the top level index.html add the embedded readme into
    # index.html
    if [ "${display_current_folder}" == "" ]; then
        # add the readme to every index
        cat ${TMP_INDEX_EMBEDDED_README_FILE} >> "${index_html_file}";
    else
        cat <<________EOF >> "${index_html_file}"
    <h1>
      ${TMP_OPTION_REPOSITORY_TITLE}
    </h1>
    <div class="jumbotron text-center">
      <a class="btn btn-primary btn-lg"
         href="${relative_base_folder}/index.html"
         role="button">
      Click here for repository setup instructions
      </a>
    </div>
________EOF
    fi

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # add the header for the file listing
    cat <<____EOF >> "${index_html_file}"
  <hr />
  <div class="panel panel-default">
    <div class="panel-heading">
      <h3>${directory_header}</h3>
    </div>
____EOF

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # if style is 'github-pages' then add a note about GitHub not supporting
    # viewing the files because of the mime-types
    if [ "${TMP_OPTION_STYLE}" == "github-pages" ]; then
        cat <<________EOF >> "${index_html_file}"
    <div class="panel-body">
        <strong>Please note, GitHub Pages does not support proper mime-types
        for you to view the files themselves.</strong>
    </div>
________EOF
    fi

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # begin the file listings table
    cat <<____EOF >> "${index_html_file}"
    <table class="table">
      <thead>
      </thead>
      <tbody>
    ${parent_directory_html}
____EOF

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # get the array of all the file system items in this folder
    # group them by directories
    readarray -t filesystem_items < <(\
        ls \
            -1 \
            --group-directories-first \
            "${current_folder}" \
        );

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # go over all the files in the current folder, ignoring files starting
    # with "."
    for item_name in "${filesystem_items[@]}"; do

        # item with full path
        filesystem_item="${current_folder}/${item_name}";

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
        # do not include links to index.html files themselves
        if [ "${item_name}" == "index.html" ]; then
            continue;
        fi

        # check if the filesystem_item is one we handle
        if _filesystem_item_check "${filesystem_item}"; then

            # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
            # get the last modified UTC date of the filesystem_item for use
            # laters
            filesystem_item_date=$(date \
                +"%Y-%m-%d %R %Z %z" \
                --date \
                @$(stat -c %Y "${filesystem_item}"));

            # get filesystem item size and icon
            if [ -f "${filesystem_item}" ]; then
                # get human readable file size of a file
                filesystem_item_size=$(\
                    ls \
                        --size \
                        --human-readable \
                        --directory \
                        -1 "${filesystem_item}" \
                    | cut -d' ' -f1);
                filesystem_item_icon="glyphicon-file"
            elif [ -d "${filesystem_item}" ]; then
                # folders have no file sizes
                filesystem_item_size="";
                filesystem_item_icon="glyphicon-folder-close";
            else
                # unknown filesystem items also get no file sizes
                filesystem_item_size="";
                # use "?" for unknown file system items
                filesystem_item_icon="glyphicon-question-sign";
            fi

            # create url encoded url
            link_url="$(_urlencode ${item_name})";

            # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
            # generate the table row with link, date and size
            cat <<____________EOF >> "${index_html_file}"
          <tr>
            <td>
            <span class="glyphicon ${filesystem_item_icon}"></span>
              <a href="${link_url}">${item_name}</a>
            </td>
            <td>
              ${filesystem_item_date}
            </td>
            <td>
              ${filesystem_item_size}
            </td>
          </tr>
____________EOF

        else
            # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
            # warn when skipping symlinks
            # TODO: support symlinks that link within the repository
            echo "! skipping symlink as unsupported: ${filesystem_item}">&2;
        fi;
    done;

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # close of the listing block and body and html tags
    cat <<____EOF >> "${index_html_file}"
      </tbody>
    </table>
  </div>
____EOF

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
    # close html document
    _html_document_ending_to_file \
        "${index_html_file}";

}


# ........................................................................... #
# write of the html document to a given file, and give title
# $1: file which html will be written
# $2: base of the document (used for css inclusion)
# $3: contents of the title tag
function _html_document_beginning_to_file {

    local html_file;
    local title_html;
    local base_folder;

    html_file="${1}";
    base_folder="${2}";
    title_html="${3}"

    cat <<____EOF > "${html_file}"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <!-- The above 3 meta tags *must* come first in the head; any other head content must come *after* these tags -->
  <title>${title_html}</title>
  <link rel="stylesheet" href="${base_folder}/_static/css/bootstrap.min.css">

  <style type="text/css">
    body {
      padding-bottom: 50px;
   }
   /* for some reason the last row is too high */
   table {
      margin-bottom: 0px !important; */
   }
  </style>

</head>
<body>
<div class="container">
____EOF

}

# ........................................................................... #
# write ending of the html document to a given file
# $1: the file to cat the html tp
function _html_document_ending_to_file {

    local html_file;
    html_file="${1}";

    cat <<____EOF >> "${html_file}"
  <hr />
  <div class="pull-right">
    Repository created on: $(date +"%Y-%m-%d %R %Z %z")
  </div>
</div>
</body>
</html>
____EOF


}


# ........................................................................... #
# check given file system item to see if is acceptable to generate a link from
function _filesystem_item_check {

    local filesystem_item;
    filesystem_item="${1}";

    # do not allow ANY symlinks (even valid ones)
    if [ -h "${filesystem_item}" ]; then
        return 1;
    fi

    # allow regule files
    if [ -f "${filesystem_item}" ]; then
        return 0;
    fi

    # allow directories
    if [ -d "${filesystem_item}" ]; then
        return 0;
    fi

    # otherwise error out
    return 1;

}

# ........................................................................... #
# url encode functions
# https://gist.github.com/cdown/1163649#gistcomment-1914130
# $1: url to encode
function _urlencode() {

    local raw_url;
    local LANG;

    raw_url="${1}";

    lang=C;
    for ((i=0;i<${#1};i++)); do
        if [[ ${raw_url:$i:1} =~ ^[a-zA-Z0-9\.\~\_\-]$ ]]; then
            printf "${raw_url:$i:1}"
        else
            printf '%%%02X' "'${raw_url:$i:1}"
        fi
    done
}

# ........................................................................... #
# add style specific files
function add_style_specific_stylings {

    local github_readme_file;

    # for github-pages create a README.me with the contents of the embedded HTML
    # this way the instructions can be displayed inline in the repository
    # itself
    if [ "${TMP_OPTION_STYLE}" == "github-pages" ]; then

        github_readme_file="${TMP_WORK_REPOSITORY_FOLDER}/README.md";

        # add the html beginning
        # this differs from the _html_document_beginning_to_file because
        # it does not add doctype which shows as pure text in an .md file
        # it also does not add any of css stylesing or title which do not
        # get rendered anyhow on github
        cat <<________EOF > "${github_readme_file}"
<html>
<body>
<div class="container">
________EOF

        # add the embedded file
        cat \
            "${TMP_INDEX_EMBEDDED_README_FILE}" \
        >> "${github_readme_file}";

        # add the endsing
        _html_document_ending_to_file \
            "${github_readme_file}";

    fi

}


# ........................................................................... #
# copy static assets to the output folder
function copy_static_assets {

    cp \
        ${TMP_CP_VERBOSITY} \
        --recursive \
        "${TMP_STATIC_ASSETS_FOLDER}" \
        "${TMP_OPTION_OUTPUT_FOLDER}";

}


# ........................................................................... #
# copy the repository over the working folder
function copy_repository_to_output_folder {

    cp \
        ${TMP_CP_VERBOSITY} \
        --recursive \
        --no-target-directory \
        "${TMP_WORK_REPOSITORY_FOLDER}" \
        "${TMP_OPTION_OUTPUT_FOLDER}";
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
