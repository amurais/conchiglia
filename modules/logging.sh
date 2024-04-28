#!/usr/bin/env bash

# Configurables

_TZ="${LOGGING_TZ:-UTC}" # tz format, usually continent/city
_LOG_LEVEL="${LOGGING_LEVEL:-D}"
_LOG_STDOUT="${LOGGING_STDOUT:-true}"
_LOG_CALL_STACK="${LOGGING_CALL_STACK:-true}"
_TIME_FMT="${LOGGING_TIME_FMT:-%Y-%m-%dT%H:%M:%S.%3N%:z}"
_JSON="${LOGGING_JSON:-true}"

if [[ -v LOGGING_FILES ]]; then
    _LOG_FILES=("${LOGGING_FILES[@]}")
else
    _LOG_FILES=()
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
        elif ! printf "%f" "$(date +"${_TIME_FMT}")" > /dev/null 2>&1; then
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

    [[ "${severity}" -gt "$(getSeverity "${_LOG_LEVEL}")" ]] && return 0

    time_str="$(TZ="${_TZ}" "${_DATE_CMD}" +"${_TIME_FMT}")"

    [[ "${_LOG_CALL_STACK}" == true ]] && {
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
            "${call_stack_str:-}" | tee -a "${_LOG_FILES[@]}" > ${_O_PIPE}
    fi
}


main () {
    if [[ "${_LOG_STDOUT,,}" == true ]]; then
        _O_PIPE='/dev/stdout'
    else
        _O_PIPE='/dev/null'
    fi

    _DATE_CMD=$(selectDateCmd)

    logging::log 'INFO' \
        "Logger initialized. Timezone=${_TZ}, call stack=${_LOG_CALL_STACK}"
}


main "$@"
