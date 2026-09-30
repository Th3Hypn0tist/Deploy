#!/usr/bin/env bash

SCHEMA_COMPONENT_NAMES=()
SCHEMA_COMPONENT_INIT_FILES=()
SCHEMA_COMPONENT_MIGRATION_DIRS=()
SCHEMA_COMPONENT_TARGETS=()
SCHEMA_COMPONENT_CONFIG_FILES=()

schema_reset() {
    SCHEMA_COMPONENT_NAMES=()
    SCHEMA_COMPONENT_INIT_FILES=()
    SCHEMA_COMPONENT_MIGRATION_DIRS=()
    SCHEMA_COMPONENT_TARGETS=()
    SCHEMA_COMPONENT_CONFIG_FILES=()
}

schema_component_add() {
    local name="$1"
    local init_file="$2"
    local migration_dir="$3"
    local target="$4"
    local config_file="${5:-config.php}"

    [[ -n "${name}" ]] || {
        echo "ERROR: schema component name is empty" >&2
        return 1
    }

    [[ "${init_file}" != /* && "${init_file}" != *".."* ]] || {
        echo "ERROR: init file must be a safe repo-relative path: ${init_file}" >&2
        return 1
    }

    [[ "${migration_dir}" != /* && "${migration_dir}" != *".."* ]] || {
        echo "ERROR: migration directory must be a safe repo-relative path: ${migration_dir}" >&2
        return 1
    }

    [[ "${target}" == /* ]] || {
        echo "ERROR: schema runner target must be absolute: ${target}" >&2
        return 1
    }

    [[ "${config_file}" != */* && "${config_file}" != *".."* ]] || {
        echo "ERROR: schema config must be a target-root filename: ${config_file}" >&2
        return 1
    }

    SCHEMA_COMPONENT_NAMES+=("${name}")
    SCHEMA_COMPONENT_INIT_FILES+=("${init_file}")
    SCHEMA_COMPONENT_MIGRATION_DIRS+=("${migration_dir}")
    SCHEMA_COMPONENT_TARGETS+=("${target}")
    SCHEMA_COMPONENT_CONFIG_FILES+=("${config_file}")
}

schema_has_components() {
    (( ${#SCHEMA_COMPONENT_NAMES[@]} > 0 ))
}

_schema_sha256() {
    sha256sum -- "$1" | awk '{print $1}'
}

_schema_identity() {
    local file="$1"
    local base stem ext actual existing human

    [[ -f "${file}" ]] || {
        echo "ERROR: SQL file not found: ${file}" >&2
        return 1
    }

    base="$(basename -- "${file}")"

    [[ "${base}" == *.* ]] || {
        echo "ERROR: SQL filename requires an extension: ${base}" >&2
        return 1
    }

    ext="${base##*.}"
    stem="${base%.*}"

    [[ "${ext,,}" == "sql" ]] || {
        echo "ERROR: SQL artifact must use .sql: ${base}" >&2
        return 1
    }

    [[ -n "${stem}" && "${stem}" != *_ ]] || {
        echo "ERROR: SQL filename stem must not end in '_': ${base}" >&2
        return 1
    }

    actual="$(_schema_sha256 "${file}")"

    if [[ "${stem}" =~ ^(.+)_([0-9a-fA-F]{64})$ ]]; then
        human="${BASH_REMATCH[1]}"
        existing="${BASH_REMATCH[2],,}"

        [[ "${human}" != *_ ]] || {
            echo "ERROR: SQL filename stem must not end in '_': ${base}" >&2
            return 1
        }

        if [[ "${existing}" != "${actual}" ]]; then
            echo "ERROR: SQL filename hash does not match exact file bytes: ${base}" >&2
            echo "Filename: ${existing}" >&2
            echo "Actual:   ${actual}" >&2
            return 1
        fi

        SCHEMA_SQL_NAME="${base}"
        SCHEMA_SQL_HASH="${actual}"
        return 0
    fi

    SCHEMA_SQL_NAME="${stem}_${actual}.${ext}"
    SCHEMA_SQL_HASH="${actual}"
}

_schema_runner_name() {
    local stamp
    stamp="$(date -u +'%Y-%m-%dT%H:%M:%S.%N')"
    printf '%s' "${stamp}:${BASHPID}:${RANDOM}" \
        | sha256sum \
        | awk '{print $1 ".php"}'
}

_schema_php_literal() {
    python3 - "$1" <<'PY'
import sys
v = sys.argv[1]
print("'" + v.replace("\\", "\\\\").replace("'", "\\'") + "'")
PY
}

_schema_generate_runner() {
    local sql_file="$1"
    local component="$2"
    local config_file="$3"
    local mode="$4"
    local runner_file="$5"
    local init_sql="${6:-}"

    _schema_identity "${sql_file}"

    local sql_b64 init_b64
    sql_b64="$(base64 -w 0 -- "${sql_file}")"
    init_b64="$(printf '%s' "${init_sql}" | base64 -w 0)"

    local q_component q_name q_hash q_config q_mode q_sql q_init
    q_component="$(_schema_php_literal "${component}")"
    q_name="$(_schema_php_literal "${SCHEMA_SQL_NAME}")"
    q_hash="$(_schema_php_literal "${SCHEMA_SQL_HASH}")"
    q_config="$(_schema_php_literal "${config_file}")"
    q_mode="$(_schema_php_literal "${mode}")"
    q_sql="$(_schema_php_literal "${sql_b64}")"
    q_init="$(_schema_php_literal "${init_b64}")"

    cat > "${runner_file}" <<'PHP'
<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Robots-Tag: noindex, nofollow');

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    echo json_encode(['ok' => false, 'error' => 'method not allowed']);
    exit;
}

$component = __AIGM_COMPONENT__;
$migrationName = __AIGM_NAME__;
$sqlHash = __AIGM_HASH__;
$configFile = __AIGM_CONFIG__;
$mode = __AIGM_MODE__;
$sqlBase64 = __AIGM_SQL__;
$initSqlBase64 = __AIGM_INIT__;

function fail_response(int $status, string $message): never {
    http_response_code($status);
    echo json_encode(
        ['ok' => false, 'error' => $message],
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
    );
    exit;
}

try {
    $configPath = __DIR__ . DIRECTORY_SEPARATOR . $configFile;

    if (!is_file($configPath)) {
        throw new RuntimeException('database config file missing');
    }

    $config = require $configPath;

    if (!is_array($config)) {
        throw new RuntimeException('database config must return an array');
    }

    $externalPath = trim((string)($config['db_config'] ?? ''));

    if ($externalPath !== '') {
        if (!is_file($externalPath)) {
            throw new RuntimeException('external database config file missing');
        }

        $external = require $externalPath;

        if (!is_array($external)) {
            throw new RuntimeException('external database config must return an array');
        }

        $config = array_replace($config, $external);
    }

    $dsn = (string)($config['dsn'] ?? '');
    $user = (string)($config['user'] ?? '');
    $password = (string)($config['password'] ?? '');

    if ($dsn === '' || $user === '') {
        throw new RuntimeException('database configuration incomplete');
    }

    $sql = base64_decode($sqlBase64, true);

    if (!is_string($sql)) {
        throw new RuntimeException('embedded SQL decode failed');
    }

    if (!hash_equals($sqlHash, hash('sha256', $sql))) {
        throw new RuntimeException('embedded SQL hash mismatch');
    }

    $pdo = new PDO(
        $dsn,
        $user,
        $password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::MYSQL_ATTR_MULTI_STATEMENTS => true,
        ]
    );

    $pdo->exec("SET time_zone = '+00:00'");

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS AIGM_schema_history (
            migration_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            component VARCHAR(64) NOT NULL,
            migration_name VARCHAR(255) NOT NULL,
            sql_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
            applied_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            PRIMARY KEY (migration_id),
            UNIQUE KEY uq_AIGM_schema_history_sql_hash (sql_hash),
            KEY idx_AIGM_schema_history_component (component, migration_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
    );

    $locked = $pdo->query(
        "SELECT GET_LOCK('AIGM_schema_migration', 30)"
    )->fetchColumn();

    if ((string)$locked !== '1') {
        fail_response(503, 'schema migration lock unavailable');
    }

    try {
        $existing = $pdo->prepare(
            "SELECT migration_id, component, migration_name, sql_hash, applied_at
             FROM AIGM_schema_history
             WHERE sql_hash = ?
             LIMIT 1"
        );
        $existing->execute([$sqlHash]);
        $row = $existing->fetch();

        if (is_array($row)) {
            echo json_encode(
                [
                    'ok' => true,
                    'status' => 'already_applied',
                    'migration' => $row,
                ],
                JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
            );
            exit;
        }

        if ($mode === 'init') {
            $componentHistory = $pdo->prepare(
                "SELECT COUNT(*)
                 FROM AIGM_schema_history
                 WHERE component = ?"
            );
            $componentHistory->execute([$component]);

            if ((int)$componentHistory->fetchColumn() > 0) {
                fail_response(409, 'component already initialized');
            }
        }

        $pdo->exec($sql);

        if ($mode === 'init' && $initSqlBase64 !== '') {
            $initSql = base64_decode($initSqlBase64, true);

            if (!is_string($initSql)) {
                throw new RuntimeException('embedded init SQL decode failed');
            }

            $pdo->exec($initSql);
        }

        $insert = $pdo->prepare(
            "INSERT INTO AIGM_schema_history
                (component, migration_name, sql_hash)
             VALUES (?, ?, ?)"
        );
        $insert->execute([$component, $migrationName, $sqlHash]);

        $id = (int)$pdo->lastInsertId();

        $read = $pdo->prepare(
            "SELECT migration_id, component, migration_name, sql_hash, applied_at
             FROM AIGM_schema_history
             WHERE migration_id = ?"
        );
        $read->execute([$id]);

        echo json_encode(
            [
                'ok' => true,
                'status' => 'applied',
                'migration' => $read->fetch(),
            ],
            JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
        );
    } finally {
        try {
            $pdo->query("SELECT RELEASE_LOCK('AIGM_schema_migration')");
        } catch (Throwable $ignored) {
        }
    }
} catch (Throwable $e) {
    error_log(
        '[AIGM schema runner] '
        . get_class($e)
        . ': '
        . $e->getMessage()
    );
    fail_response(500, 'schema migration failed');
}
PHP

    AIGM_Q_COMPONENT="${q_component}" \
    AIGM_Q_NAME="${q_name}" \
    AIGM_Q_HASH="${q_hash}" \
    AIGM_Q_CONFIG="${q_config}" \
    AIGM_Q_MODE="${q_mode}" \
    AIGM_Q_SQL="${q_sql}" \
    AIGM_Q_INIT="${q_init}" \
    python3 - "${runner_file}" <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

mapping = {
    "__AIGM_COMPONENT__": os.environ["AIGM_Q_COMPONENT"],
    "__AIGM_NAME__": os.environ["AIGM_Q_NAME"],
    "__AIGM_HASH__": os.environ["AIGM_Q_HASH"],
    "__AIGM_CONFIG__": os.environ["AIGM_Q_CONFIG"],
    "__AIGM_MODE__": os.environ["AIGM_Q_MODE"],
    "__AIGM_SQL__": os.environ["AIGM_Q_SQL"],
    "__AIGM_INIT__": os.environ["AIGM_Q_INIT"],
}

for key, value in mapping.items():
    text = text.replace(key, value)

if "__AIGM_" in text:
    raise SystemExit("runner template placeholder remained unresolved")

path.write_text(text, encoding="utf-8")
PY
}

_schema_execute() {
    local component="$1"
    local sql_file="$2"
    local target="$3"
    local config_file="$4"
    local mode="$5"
    local init_sql="${6:-}"

    command -v sha256sum >/dev/null 2>&1 || {
        echo "ERROR: sha256sum is required" >&2
        return 1
    }

    command -v base64 >/dev/null 2>&1 || {
        echo "ERROR: base64 is required" >&2
        return 1
    }

    command -v php >/dev/null 2>&1 || {
        echo "ERROR: php is required" >&2
        return 1
    }

    command -v curl >/dev/null 2>&1 || {
        echo "ERROR: curl is required" >&2
        return 1
    }

    _schema_identity "${sql_file}"

    local runner_name runner_file uploaded=false
    runner_name="$(_schema_runner_name)"
    runner_file="$(mktemp --suffix=.php)"

    cleanup_schema_runner() {
        local cleanup_rc=0

        if [[ "${uploaded}" == "true" ]]; then
            if ! transport_remove_file "${target}" "${runner_name}"; then
                echo "ERROR: failed to remove remote runner: ${runner_name}" >&2
                cleanup_rc=1
            fi
        fi

        rm -f -- "${runner_file}"
        uploaded=false
        return "${cleanup_rc}"
    }

    trap cleanup_schema_runner RETURN

    _schema_generate_runner \
        "${sql_file}" \
        "${component}" \
        "${config_file}" \
        "${mode}" \
        "${runner_file}" \
        "${init_sql}"

    php -l "${runner_file}" >/dev/null

    echo
    echo "----------------------------------------------------------------"
    echo "Database:   ${component}"
    echo "Mode:       ${mode}"
    echo "SQL source: ${sql_file}"
    echo "Artifact:   ${SCHEMA_SQL_NAME}"
    echo "SQL hash:   ${SCHEMA_SQL_HASH}"
    echo "Runner:     ${runner_name}"
    echo "Target:     ${target}"
    echo "----------------------------------------------------------------"

    transport_upload_file "${runner_file}" "${target}" "${runner_name}"
    uploaded=true

    local url response
    url="https://${DOMAIN}${target%/}/${runner_name}"

    if ! response="$(
        curl \
            --fail-with-body \
            --silent \
            --show-error \
            --max-time 120 \
            -X POST \
            -H 'Accept: application/json' \
            "${url}"
    )"; then
        echo "ERROR: schema runner request failed" >&2
        return 1
    fi

    python3 - "${response}" <<'PY'
import json
import sys

raw = sys.argv[1]

try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("ERROR: runner returned invalid JSON", file=sys.stderr)
    print(raw, file=sys.stderr)
    raise SystemExit(1)

if data.get("ok") is not True:
    print("ERROR: runner failed", file=sys.stderr)
    print(json.dumps(data, ensure_ascii=False), file=sys.stderr)
    raise SystemExit(1)

migration = data.get("migration") or {}

print()
print(f"Status:       {data.get('status', 'unknown')}")
if "migration_id" in migration:
    print(f"Migration ID: {migration['migration_id']}")
if "component" in migration:
    print(f"Component:    {migration['component']}")
if "migration_name" in migration:
    print(f"Artifact:     {migration['migration_name']}")
if "sql_hash" in migration:
    print(f"SQL hash:     {migration['sql_hash']}")
if "applied_at" in migration:
    print(f"Applied at:   {migration['applied_at']} UTC")
PY

    cleanup_schema_runner
    trap - RETURN
}

schema_validate_init_all() {
    if ! schema_has_components; then
        return 0
    fi

    local i
    for i in "${!SCHEMA_COMPONENT_NAMES[@]}"; do
        local component="${SCHEMA_COMPONENT_NAMES[$i]}"
        local init_file="${LOCAL_REPO}/${SCHEMA_COMPONENT_INIT_FILES[$i]}"

        [[ -f "${init_file}" ]] || {
            echo "ERROR: init SQL missing for ${component}: ${init_file}" >&2
            return 1
        }

        _schema_identity "${init_file}"

        echo "Init preflight: ${component}"
        echo "  source:   ${init_file}"
        echo "  artifact: ${SCHEMA_SQL_NAME}"
        echo "  hash:     ${SCHEMA_SQL_HASH}"
    done
}

schema_init_all() {
    if ! schema_has_components; then
        return 0
    fi

    local i
    for i in "${!SCHEMA_COMPONENT_NAMES[@]}"; do
        local component="${SCHEMA_COMPONENT_NAMES[$i]}"
        local init_file="${LOCAL_REPO}/${SCHEMA_COMPONENT_INIT_FILES[$i]}"
        local target="${SCHEMA_COMPONENT_TARGETS[$i]}"
        local config="${SCHEMA_COMPONENT_CONFIG_FILES[$i]}"
        local bootstrap=""

        [[ -f "${init_file}" ]] || {
            echo "ERROR: init SQL missing: ${init_file}" >&2
            return 1
        }

        _schema_identity "${init_file}"

        echo
        echo "================================================================"
        echo "DATABASE INIT: ${component}"
        echo "================================================================"
        echo "Artifact: ${SCHEMA_SQL_NAME}"
        echo

        if declare -F schema_init_prepare >/dev/null 2>&1; then
            SCHEMA_INIT_SQL=""
            schema_init_prepare "${component}"
            bootstrap="${SCHEMA_INIT_SQL:-}"
            unset SCHEMA_INIT_SQL
        fi

        _schema_execute \
            "${component}" \
            "${init_file}" \
            "${target}" \
            "${config}" \
            "init" \
            "${bootstrap}"

        unset bootstrap
    done
}

_schema_select_component() {
    local count="${#SCHEMA_COMPONENT_NAMES[@]}"

    if (( count == 1 )); then
        SCHEMA_SELECTED_COMPONENT=0
        return 0
    fi

    echo
    echo "DATABASE COMPONENT"
    echo

    local i
    for i in "${!SCHEMA_COMPONENT_NAMES[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${SCHEMA_COMPONENT_NAMES[$i]}"
    done

    echo
    echo "  0) Cancel"
    echo

    local choice
    read -r -p "Select: " choice

    if [[ "${choice}" == "0" ]]; then
        return 2
    fi

    [[ "${choice}" =~ ^[0-9]+$ ]] || {
        echo "ERROR: invalid component selection" >&2
        return 1
    }

    local index=$((choice - 1))

    (( index >= 0 && index < count )) || {
        echo "ERROR: component does not exist" >&2
        return 1
    }

    SCHEMA_SELECTED_COMPONENT="${index}"
}

_schema_select_migration() {
    local index="$1"
    local dir="${LOCAL_REPO}/${SCHEMA_COMPONENT_MIGRATION_DIRS[$index]}"
    local files=()

    [[ -d "${dir}" ]] || {
        echo "ERROR: migration directory missing: ${dir}" >&2
        return 1
    }

    while IFS= read -r -d '' file; do
        files+=("${file}")
    done < <(
        find "${dir}" -maxdepth 1 -type f -name '*.sql' -print0 | sort -z
    )

    if (( ${#files[@]} == 0 )); then
        echo "No migrations found in ${dir}."
        return 2
    fi

    echo
    echo "MIGRATIONS"
    echo

    local i
    for i in "${!files[@]}"; do
        _schema_identity "${files[$i]}"
        printf "  %d) %s\n" "$((i + 1))" "${SCHEMA_SQL_NAME}"
    done

    echo
    echo "  0) Cancel"
    echo

    local choice
    read -r -p "Select migration: " choice

    if [[ "${choice}" == "0" ]]; then
        return 2
    fi

    [[ "${choice}" =~ ^[0-9]+$ ]] || {
        echo "ERROR: invalid migration selection" >&2
        return 1
    }

    local selected=$((choice - 1))

    (( selected >= 0 && selected < ${#files[@]} )) || {
        echo "ERROR: migration does not exist" >&2
        return 1
    }

    SCHEMA_SELECTED_SQL="${files[$selected]}"
}

schema_migration_menu() {
    schema_has_components || {
        echo "ERROR: target defines no schema component" >&2
        return 1
    }

    if ! _schema_select_component; then
        local rc=$?
        (( rc == 2 )) && { echo "Cancelled."; return 0; }
        return "${rc}"
    fi

    local i="${SCHEMA_SELECTED_COMPONENT}"

    if ! _schema_select_migration "${i}"; then
        local rc=$?
        (( rc == 2 )) && { echo "Cancelled."; return 0; }
        return "${rc}"
    fi

    local component="${SCHEMA_COMPONENT_NAMES[$i]}"
    local target="${SCHEMA_COMPONENT_TARGETS[$i]}"
    local config="${SCHEMA_COMPONENT_CONFIG_FILES[$i]}"

    _schema_identity "${SCHEMA_SELECTED_SQL}"

    echo
    echo "Migration:"
    echo "  ${SCHEMA_SQL_NAME}"
    echo

    if ! confirm_yes_no "Apply to ${component}?" "false"; then
        echo "Cancelled."
        return 0
    fi

    _schema_execute \
        "${component}" \
        "${SCHEMA_SELECTED_SQL}" \
        "${target}" \
        "${config}" \
        "migration"
}
