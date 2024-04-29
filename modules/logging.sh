#!/usr/bin/env bash
: '
Logging module for bash.

The module provides a both plaintext logging and JSON logging. Configuration
can be provided in two ways:

- JSON Configuration File
- Environment Variables


*/* JSON Configuration file */*

Before sourcing the module set the LOGGING_CONFIG_FILE to point
to a JSON configuration file (LOGGING_CONFIG_FILE=config.json).
The file needs to have the following structure (default values are shown):

{
    "logging": {
        "timezone": "UTC",
        "level": "DEBUG",
        "stdout_enabled": true,
        "include_call_stack": true,
        "timestamp_fmt": "-%Y-%m-%dT%H:%M:%S.%3N%:z",
        "json": true,
        "logfiles": [
            "logging.log"
        ]
    }
}


*/* Environment Variables */*

Environment variables take precedence over settings defined via the
JSON cofig. The following environment variables can be set before sourcing
the module (default values are shown):

- LOGGING_TZ                    string          UTC
- LOGGING_LEVEL                 string          DEBUG
- LOGGING_STDOUT                bool            true
- LOGGING_INCLUDE_CALL_STACK    bool            true
- LOGGING_TIMESTAMP_FMT         string          -%Y-%m-%dT%H:%M:%S.%3N%:z
- LOGGING_JSON                  bool            true
- LOGGING_FILES                 array(str)      ( "logging.log" )


-- Usage --

Log a message:

logging::log 'I' "This is a log message"

'

# shellcheck disable=SC2046
if [[ -f "${LOGGING_CONFIG_FILE}" ]]; then

    if ! jq . "${LOGGING_CONFIG_FILE}" > /dev/null 2>&1; then
        echo "[WARNING] [logging.sh] The file provided is not valid JSON"
    fi

    IFS=, read -r \
        FILE_TZ \
        FILE_LEVEL \
        FILE_STDOUT \
        FILE_INCLUDE_CALL_STACK \
        FILE_TIMESTAMP_FMT \
        FILE_JSON <<< $(jq -r '
        .logging | [
            .timezone,
            .level,
            .stdout_enabled,
            .include_call_stack,
            .timestamp_fmt,
            .json
        ] | join(",")' "${LOGGING_CONFIG_FILE}" 2> /dev/null
        )

    IFS=, read -r -a FILE_FILES <<< $(
        jq -r '.logging.logfiles // [] | join(",")' "${LOGGING_CONFIG_FILE}"
        )
fi

_TZ="${LOGGING_TZ:-${FILE_TZ:-UTC}}"
_LEVEL="${LOGGING_LEVEL:-${FILE_LEVEL:-D}}"
_STDOUT="${LOGGING_STDOUT:-${FILE_STDOUT:-true}}"
_INCLUDE_CALL_STACK="${LOGGING_INCLUDE_CALL_STACK:-${FILE_INCLUDE_CALL_STACK:-true}}"
_TIMESTAMP_FMT="${LOGGING_TIMESTAMP_FMT:-${FILE_TIMESTAMP_FMT:-%Y-%m-%dT%H:%M:%S.%3N%:z}}"
_JSON="${LOGGING_JSON:-${FILE_JSON:-true}}"


if [[ -v "${LOGGING_FILES}" ]]; then
    _LOG_FILES=("${LOGGING_FILES[@]}")
elif [[ -n "${FILE_FILES[*]}" ]]; then
    _LOG_FILES=("${FILE_FILES[@]}")
else
    _LOG_FILES=("logging.log")
fi

declare -A SEV_MSG

SEV_MSG[7]='DEBUG'
SEV_MSG[6]='INFO'
SEV_MSG[4]='WARNING'
SEV_MSG[3]='ERROR'
SEV_MSG[2]='CRITICAL'


selectDateCmd () {
    if [[ "$(uname)" == 'Darwin' ]]; then
        if command -v gdate > /dev/null; then
            echo 'gdate'
        elif ! printf "%f" "$(date +"${_TIMESTAMP_FMT}")" > /dev/null 2>&1; then
            msg="[ERROR] Either the date format is wrong or it's not compatible with BSD date. "
            msg+="Please install GNU date or change the format."
            echo "${msg}" >&2
            # return 1
        fi
    elif [[ "$(uname)" == 'Linux' ]]; then
        echo 'date'
    else
        echo "[ERROR] Platform not recognised" >&2
        # return 1
    fi
}

getSeverity () {
    local sev

    case "${1^^}" in
        D|DEBUG) sev=7 ;;
        I|INFO) sev=6 ;;
        W|WARNING) sev=4 ;;
        E|ERROR) sev=3 ;;
        C|CRITICAL) sev=2 ;;
        *)
            logger 'E' "Unknown severity '${1}', skipping log message" >&2
            return 1
            ;;
    esac

    echo "${sev}"
}

joinBy () {
    # Join using the first argument the rest of the arguments
    local _d _f

    _d="$1"; _f="${2}"
    shift 2
    printf %s "${_f}" "${@/#/$_d}"
}


outputMessage () {
    local timestamp severity message call_stack

    timestamp="${1}"
    severity="${2}"
    message="${3}"
    call_stack="${4}"

    printf "%s::%s::%s::%s\n" \
        "${timestamp}" \
        "${severity}" \
        "${message}" \
        "${call_stack_str:-}"
}


_json_escape_str () {
    local str

    str="${1}"

    str="${str//\\/\\\\}"    # replace \ with \\
    str="${str//\//\\/}"     # replace / with \/
    str="${str//\"/\\\"}"    # replace " with \""
    str="${str//$'\b'/"\b"}" # replace backspace with literal \b
    str="${str//$'\f'/"\f"}" # replace formfeed with literal \f
    str="${str//$'\n'/"\n"}" # replace newline with literal \n
    str="${str//$'\r'/"\r"}" # replace carriage return with literal \r
    str="${str//$'\t'/"\t"}" # replace horizontal tab with literal \t

    echo "${str}"
}


jsonMessage () {
    local timestamp severity message call_stack

    timestamp="${1}"
    severity="${2}"
    message="${3}"
    call_stack="${4}"

    if [[ -n "${call_stack}" ]]; then
        call_stack='"'"${call_stack}"'"'
    else
        call_stack=null
    fi

    func_idx=$(( "${#FUNCNAME[@]}" - 2))

    printf '{"timestamp": "%s", "severity": "%s", "message": "%s", "filename": "%s", "funcname": "%s", "call_stack": %s }\n' \
        "${timestamp}" \
        "${severity}" \
        "$(_json_escape_str "${message}")" \
        "${BASH_SOURCE["${func_idx}"]##*/}" \
        "${FUNCNAME["${func_idx}"]}" \
        "${call_stack}"
}


logging::log () {
    local severity message time_str call_stack call_stack_str ind

    severity="$(getSeverity "${1}")" || return 0
    message="${2}"

    [[ "${severity}" -gt "$(getSeverity "${_LEVEL}")" ]] && return 0

    time_str="$(TZ="${_TZ}" "${_DATE_CMD}" +"${_TIMESTAMP_FMT}")"

    [[ "${_INCLUDE_CALL_STACK}" == true ]] && {
        call_stack=()
        for (( ind="${#FUNCNAME[@]}" - 2; ind >=1; ind-- )); do
            call_stack+=("${BASH_SOURCE["${ind}"]##*/}[${BASH_LINENO["${ind}"]}]>${FUNCNAME["${ind}"]}")
        done

        call_stack_str="$(joinBy '->' "${call_stack[@]:-root}")"
    }

    if [[ "${_JSON}" == true ]]; then
        jsonMessage \
            "${time_str}" \
            "${SEV_MSG["${severity}"]}" \
            "${message}" \
            "${call_stack_str:-}" | tee -a "${_LOG_FILES[@]}" > "${_O_PIPE}"
    else
        outputMessage \
            "${time_str}" \
            "${SEV_MSG["${severity}"]}" \
            "${message}" \
            "${call_stack_str:-}" | tee -a "${_LOG_FILES[@]}" > "${_O_PIPE}"
    fi
}


main () {
    if [[ "${_STDOUT,,}" == true ]]; then
        _O_PIPE='/dev/stdout'
    else
        _O_PIPE='/dev/null'
    fi

    _DATE_CMD=$(selectDateCmd)

    logging::log 'INFO' \
        "Logging initialized: Timezone=${_TZ}, LogLevel=${_LEVEL} CallStack=${_INCLUDE_CALL_STACK}, JSON=${_JSON}"
}


main
