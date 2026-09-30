#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "${TARGET_DIR}/../lib/config.sh"
source "${TARGET_DIR}/../lib/ui.sh"
source "${TARGET_DIR}/../lib/repo.sh"
source "${TARGET_DIR}/../lib/b-selectah.sh"
source "${TARGET_DIR}/../lib/unit-selectah.sh"
source "${TARGET_DIR}/../lib/transport.sh"
source "${TARGET_DIR}/../lib/schema.sh"
source "${TARGET_DIR}/../lib/deploy.sh"

DOMAIN="aigm.fi"
TARGET_NAME="IAM"
TRANSPORT="ftp"

REPO_URL="https://github.com/Th3Hypn0tist/IAM.git"
LOCAL_REPO="${HOME}/AIGM/IAM"

define_units() {
    deploy_unit_add \
        "IAM" \
        "php-light" \
        "/iam" \
        "README.md;schema.sql;config.example.php;migrations;migrations/**" \
        "config.php"
}

define_schema() {
    schema_component_add \
        "IAM" \
        "php-light/schema.sql" \
        "php-light/migrations" \
        "/iam" \
        "config.php"
}

_iam_hex() {
    php -r 'echo bin2hex(stream_get_contents(STDIN));'
}

schema_init_prepare() {
    local component="$1"
    [[ "${component}" == "IAM" ]] || return 0

    command -v php >/dev/null 2>&1 || {
        echo "ERROR: php is required for IAM Origin bootstrap" >&2
        return 1
    }

    echo
    echo "IAM ORIGIN"
    echo "user_id: 0"
    echo

    local username email password password2 password_hash
    read -r -p "Username [origin]: " username
    username="${username:-origin}"

    if (( ${#username} < 3 || ${#username} > 32 )) \
        || [[ ! "${username}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "ERROR: username must be 3-32 chars: A-Z a-z 0-9 _ . -" >&2
        return 1
    fi

    read -r -p "Email: " email
    email="${email,,}"

    if ! printf '%s' "${email}" | php -r '
        $email = trim(stream_get_contents(STDIN));
        exit(filter_var($email, FILTER_VALIDATE_EMAIL) === false ? 1 : 0);
    '; then
        echo "ERROR: invalid email" >&2
        return 1
    fi

    read -r -s -p "Password: " password
    echo
    read -r -s -p "Password again: " password2
    echo

    if [[ "${password}" != "${password2}" ]]; then
        unset password password2
        echo "ERROR: passwords do not match" >&2
        return 1
    fi

    if (( ${#password} < 15 || ${#password} > 1024 )); then
        unset password password2
        echo "ERROR: password must be 15-1024 characters" >&2
        return 1
    fi

    if [[ "${password}" == "${username}" ]]; then
        unset password password2
        echo "ERROR: password must differ from username" >&2
        return 1
    fi

    password_hash="$(
        printf '%s' "${password}" | php -r '
            $password = stream_get_contents(STDIN);
            $algorithm = defined("PASSWORD_ARGON2ID")
                ? PASSWORD_ARGON2ID
                : PASSWORD_DEFAULT;
            $hash = password_hash($password, $algorithm);
            if (!is_string($hash) || $hash === "") {
                exit(1);
            }
            echo $hash;
        '
    )"

    unset password password2

    local username_hex email_hex hash_hex
    username_hex="$(printf '%s' "${username}" | _iam_hex)"
    email_hex="$(printf '%s' "${email}" | _iam_hex)"
    hash_hex="$(printf '%s' "${password_hash}" | _iam_hex)"

    unset username email password_hash

    # Values are encoded as hex SQL literals to avoid quoting ambiguity.
    SCHEMA_INIT_SQL="
START TRANSACTION;

INSERT INTO IAM_users
    (user_id, username, status, verified)
VALUES
    ('0', CONVERT(0x${username_hex} USING utf8mb4), 'active', TRUE);

INSERT INTO IAM_user_accounts
    (user_id, password_hash, email, account_status)
VALUES
    (
        '0',
        CONVERT(0x${hash_hex} USING utf8mb4),
        CONVERT(0x${email_hex} USING utf8mb4),
        'active'
    );

INSERT INTO IAM_domain_memberships
    (user_id, domain_id, status)
VALUES
    ('0', 'iam', 'active'),
    ('0', 'lmts', 'active');

INSERT INTO IAM_management_tiers
    (user_id, domain_id, management_tier, status)
VALUES
    ('0', 'iam', 1337, 'active');

COMMIT;
"

    unset username_hex email_hex hash_hex
}

deploy_target_main
