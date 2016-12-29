#!/usr/bin/env bash

# ########################################################################### #
#
#  Utility functions for other bash scripts.
#
#  Requires:
#   - bash4
#   - type
#   - getopt
#   - head
#   - sed
#
#  Optional:
#   - tput (from ncurses)
#   - tty
#
#  this file is meant to be imported using 'source' from other files
#
#  Usage (from other scripts):
#
#  if [ -e $(dirname "${0}")/utils.sh ]; then
#      source $(dirname "${0}")/utils.sh;
#  else
#      echo "
#  Could not load required 'utils.sh' module.$
#
#  " >&2;
#      exit 1;
#  fi
#
#  Note: Please modify the path accordingly
#
# ########################################################################### #


# ........................................................................... #
# return getopts line
# $1 {string} - getopt short opts
# $2 {integer} - getopt long opts
# $@ {string} - getopt options
function get_getopt {

    local short_opts=${1};
    local long_opts=${2};
    shift 2;

    local opts="";

    # we do not use local here, since that operation would yield 0
    # return code, overwriting the getopt one
    opts=$(getopt -o "${short_opts}" -l "${long_opts}" -- "$@" 2>&1);
    if [ $? != 0 ]; then
       echo -e "$opts" | head -n -1 | sed 's/getopt: /    /';
       return 1;

    fi

    echo "${opts}"
}


# ........................................................................... #
# source color variables
# text color variables using ncurses tput
# if tput or tty is not available or tty does not support colors they are
# not enabled
function maybe_enable_color_vars {

    # first set all the variables to nothing
    disable_color_vars;

    cmd_exists_silent "tput" "tty" || return 0;

    # check if we are on a tty and if not return and do not use tput;
    tty -s || return 0;
    # run tput init in the subshell and if it returns any errors then we return
    $(tput init >/dev/null 2>&1) || return 0;

    TXTUND=$(tput sgr 0 1);    # Underline
    TXTBLD=$(tput bold);       # Bold
    TXTRED=$(tput setaf 1);    # Red
    TXTGRN=$(tput setaf 2);    # Green
    TXTYLW=$(tput setaf 3);    # Yellow
    TXTBLU=$(tput setaf 4);    # Blue
    TXTPUR=$(tput setaf 5);    # Purple
    TXTCYN=$(tput setaf 6);    # Cyan
    TXTWHT=$(tput setaf 7);    # White
    TXTRST=$(tput sgr0);       # Text reset
}

# ........................................................................... #
# source color variables
# Text color variables using ncurses tput
function disable_color_vars {

    TXTUND="";    # Underline
    TXTBLD="";    # Bold
    TXTRED="";    # Red
    TXTGRN="";    # Green
    TXTYLW="";    # Yellow
    TXTBLU="";    # Blue
    TXTPUR="";    # Purple
    TXTCYN="";    # Cyan
    TXTWHT="";    # White
    TXTRST="";    # Text reset

}


# ........................................................................... #
# use type -P to check for any command we need
function cmd_exists {
    local check_file=$(type -P "${1}")
    [ "x${check_file}" == "x" ] && return 1;
    return 0;
}


# ........................................................................... #
# silent version cmd_exits
function cmd_exists_silent {
    local check_file=$(type -P "${1}")
    [ "x${check_file}" == "x" ] && return 1;
    return 0;
}


# ........................................................................... #
# check multiple command and abort if not found
function cmds_exists_or_abort {
    local cmd="";
    for cmd in $@; do
        cmd_exists "${cmd}" || abort "Could not find '${cmd}' in your path" 1;
    done;
}


# ........................................................................... #
# check multiple command and abort if not found
function cmds_exists_or_abort {
    local cmd="";
    for cmd in $@; do
        cmd_exists "${cmd}" || abort "Could not find '${cmd}' in your path" 1;
    done;
}


# ........................................................................... #
# check multiple command and abort if none of found
function cmds_exists_or_abort_if_none {

    local cmd_exists=0;

    local cmd="";
    for cmd in $@; do
        cmd_exists "${cmd}"  && { cmd_exists=1; break; }
    done;

    if [ $cmd_exists == 0 ]; then
        abort "Could not find any of following '$@' in your path" 1;
    fi
}


# ........................................................................... #
# check for bash version exists and abort if none of found
function cmd_exists_bash4_or_abort {

    cmds_exists_or_abort "bash";
    if [ "x${BASH_VERSION:0:1}" != "x4" ]; then
        abort "Could not find 'bash' version 4 in your path" 1;
    fi
}

# ........................................................................... #
# check multiple command and abort if none of found
function cmd_exists_gnu_getopt_or_abort {

    local getopt_retcode;

    cmds_exists_or_abort_if_none "getopt";

    # check if getopt is gnu, by checking it's error code
    # use || true suppress the bubbled up error code due to set -E/-e
    getopt_retcode=$(getopt -T; echo $?) || true;
    if [ ${getopt_retcode} -ne 4 ]; then
        abort "Could not find 'GNU getopt' in your path" 1;
    fi

}

# ........................................................................... #
# echo yes if value is 1 and no if value is 0
# $1 {string} - boolean
function humanize_bool {
    local boolean_value="${1}";

    if [ "${boolean_value}" -eq "1" ]; then
        echo -n "yes";
    elif [ "${boolean_value}" -eq "0" ]; then
        echo -n "no"
    else
        abort "Invalid boolean value ${boolean_value}" 1;
    fi

}


# ........................................................................... #
# print out message if verbosity is enabled
function log_verbose {
    local msg="${1}";
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        echo "${msg}";
    fi
}

# ........................................................................... #
# print out message if unless quiet is enabled
function log_unquiet {
    local msg="${1}";
    if [ ${TMP_OPTION_QUIET} -eq 0 ]; then
        echo "${msg}";
    fi
}


# ........................................................................... #
# print out message if verbosity is enabled
function cat_verbose {
    local file="${1}";
    if [ ${TMP_OPTION_VERBOSE} -eq 1 ]; then
        cat "${file}";
    fi
}


# ........................................................................... #
# print out everything in gpg version up to Copyright line as comma separated
# entries
function gpg_version {

    local gpg="${1}";
    local found_copyright;
    local result="";

     # get the gpg version, go over it line by line
     "${gpg}" --version | while read line; do
        # use || true suppress the bubbled up error code due to set -E/-e
        found_copyright=$(
            # check if the line starts with a Copyright string
            echo "${line}" | grep -i ^Copyright 1>/dev/null 2>/dev/null;
            # if it does then grep return will be 0, so if grep return is not
            # 0 then echo out the return code of the test comparission
            # basicall this is a sad way to do "not $?" to invert it
            test $? -ne 0;
            echo $?;
        ) || true;
        # so if we found the Copyright string, leave the subshell
        if [ "${found_copyright}" -eq 1 ]; then
            return;
        else
            # if Copyright has not been found yet, then echo out the line
            # follow by comma and s space
            echo -n "${line}, ";
        fi
    done \
    | rev \
    | cut -c3- \
    | rev;
    # above rev/cut/rev combination is used to remove the trailing ", " chars
    # basically we reverse the string, print it from char 3 and reverse it
    # again

}


# ........................................................................... #
# echo out a given message and exit script with a give code
# $1 {string} - message to echo.
# $2 {integer} - exit code
function abort {

    local msg;
    local exit_code;
    local echo_opts="";

    if [ "x${1}" == "x-e" ]; then
        echo_opts="-e";
        shift;
    fi

    # if the colour variables are not set do not colour the message
    # TODO: maybe check all the colour variables used instead of just 1
    # https://stackoverflow.com/questions/3601515/how-to-check-if-a-variable-is-set-in-bash
    if [ -z ${TXTBLD+x} ]; then
        msg="${1}";
    else
        msg="${TXTBLD}${TXTRED}${1}${TXTRST}";
    fi


    local exit_code=${2};


    echo ${echo_opts} "${msg}

Aborting
" >&2;
    exit ${exit_code};
}


# ........................................................................... #
# abort with content of a given error log and a message
function abort_with_log {

    local error_log_file="${1}";
    local msg="${2}";
    local code="${3}";

    # close the 3 and 4 file handles used for error code redirection
    exec 3>&-;
    exec 4>&-;

    # error log might not exist is some case like where verbose moders
    # do not redirect to a log
    if [ -e "${error_log_file}" ]; then
        cat "${error_log_file}">&2;
    fi
    abort "${msg}" ${code};
}


# ........................................................................... #
# shred and remove all files recursively found in the given folder.
# checking first if the folder exists
# :{1}: - shred verbosity
# :{2}: - folder to search recursively
function shred_recursively {
    local shred_verbosity="${1}";
    local folder="${2}";

    # shred every file in the gpg homedir
    if [ -d "${folder}" ]; then
        find \
            "${folder}" \
            -type f \
        | while read file; do
            shred \
                ${shred_verbosity} \
                --force \
                --remove \
                --zero \
                "${file}";
        done
    fi
}


# ........................................................................... #
# do a less-then-or-equal comparission of two passed in versions
# :{1}: - required version
# :{2}: - test versions
function version_lte {

    local required_version;
    local test_version;
    local lowest_version;

    required_version="${1}";
    test_version="${2}";

    # get the lowest version for required and test version by sorting using
    # sort's version sort and then taking the first value
    lowest_version="$(echo -e "${required_version}\n${test_version}" \
        | sort --version-sort \
        | head --lines 1)"

    # if lowest version is the same as a required one then we are goo
    if [ "${lowest_version}" == "${required_version}" ]; then
        return 0;
    else
        return 1;
    fi

}
