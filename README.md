# AIGM Deploy Tool v2

Canonical layout:

```text
deploy/
├── do.sh
├── deploy.json          # EXISTING FILE: keep unchanged
├── lib/
└── targets/
```

`deploy.json` is intentionally NOT included in this package.

## Root operations

```text
<number> Target
    Normal code deploy for one target.
    Never touches the database.

a) All
    Deploy all targets' code.
    Never touches the database.

m) Multi
    Deploy selected targets' code.
    Never touches the database.

i) Init
    Exceptional first-install operation.
    For every target:
      1. deploy all code units
      2. execute configured canonical init SQL
    IAM Init also bootstraps Origin user_id 0.

g) Migration
    Explicit database-only operation.
    Select target/component/migration.
    Never deploys code.
```

## Target contract

A target contains two independent declarations:

```bash
define_units() {
    # code deployment only
}

define_schema() {
    # init/migration artifact locations only
}
```

Normal deploy code never calls `define_schema()` execution paths.

## SQL standard

Canonical component repository layout:

```text
schema/
├── init.sql
└── migrations/
    └── *.sql
```

IAM currently declares its existing canonical schema at:

```text
php-light/schema.sql
```

LMTS target expects:

```text
schema/init.sql
schema/migrations/
```

SQL artifact identity:

```text
SHA-256(exact SQL file bytes)
<human-stem>_<sha256>.sql
```

The source stem must not end in `_`.

The deploy tool does not rewrite the repository file. The hashed name is the
canonical execution/history artifact identity.

## Universal history

The runner owns:

```text
AIGM_schema_history
- migration_id BIGINT AUTO_INCREMENT PRIMARY KEY
- component
- migration_name
- sql_hash UNIQUE
- applied_at DATETIME(6)
```

`migration_id` is shared and incremental across components using the same DB.

## Temporary runner

SQL execution uses a separately named ephemeral PHP runner:

```text
generate runner hash
-> upload <runner-hash>.php
-> HTTP POST
-> execute/check history
-> remove runner
```

Runner hash is never persisted.

## IAM Origin

IAM Init asks for:

- username, default `origin`
- email
- password + confirmation

It creates:

```text
user_id = 0
iam membership = active
lmts membership = active
iam management tier = 1337
```

The plaintext password is never stored in a file or embedded in the runner.
Only the PHP password hash enters the temporary init payload.

## deploy.json

This package deliberately contains no `deploy.json`.

Keep the existing Homebrain `deploy.json` exactly as-is.
The existing version-1 config contract is unchanged.


## Relocatable site root

New shared-library targets use one deployment prefix:

```bash
AIGM_SITE_ROOT_PREFIX
```

If the variable is unset, the safe candidate default is:

```text
/test
```

Therefore the shared targets deploy as:

```text
/test/lib/webengine/
/test/lib/webgui/
/test/lib/s3d/
/test/style/
```

Target scripts themselves contain only canonical logical destinations:

```text
/lib/webengine
/lib/webgui
/lib/s3d
/style
```

Production cutover uses the same target scripts with an explicitly empty prefix:

```bash
AIGM_SITE_ROOT_PREFIX="" ./do.sh
```

which maps the same units to:

```text
/lib/webengine/
/lib/webgui/
/lib/s3d/
/style/
```

No source repository is rewritten and no `/test` literal becomes application semantics.

The existing IAM and LMTS production targets are intentionally left unchanged during this stage. Use the new shared mirror targets explicitly (single or multi-select) while the candidate site is under `/test`.
