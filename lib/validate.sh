# shellcheck shell=bash

validate_error() {
    local message="$1"

    printf 'Validation error: %s\n' "$message" >&2
    return 2
}

contains_control_character() {
    local value="$1"
    local LC_ALL=C

    [[ "$value" =~ [[:cntrl:]] ]]
}

contains_whitespace() {
    local value="$1"
    local LC_ALL=C

    [[ "$value" =~ [[:space:]] ]]
}

is_decimal_integer() {
    local value="$1"
    local LC_ALL=C

    [[ "$value" =~ ^[0-9]+$ ]] && (( ${#value} <= 9 ))
}

validate_required_value() {
    local variable_name="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        validation_error "${variable_name} must not be empty."
        return 2
    fi

    if contains_control_character "$value"; then
        validation_error "${variable_name} must not contain control characters."
        return 2
    fi

    return 0
}

validate_boolean() {
    local variable_name="$1"
    local value="$2"

    case "$value" in
        true|false)
            return 0
            ;;
        *)
            validation_error \
                "${variable_name} must be either true or false; received '${value}'."
            return 2
            ;;
    esac
}

validate_integer_range() {
    local variable_name="$1"
    local value="$2"
    local minimum="$3"
    local maximum="$4"
    local numeric_value=0

    if ! is_decimal_integer "$value"; then
        validation_error \
            "${variable_name} must be a decimal integer; received '${value}'."
        return 2
    fi

    numeric_value=$((10#${value}))

    if (( numeric_value < minimum || numeric_value > maximum )); then
        validation_error \
            "${variable_name} must be between ${minimum} and ${maximum}; received '${value}'."
        return 2
    fi

    return 0
}