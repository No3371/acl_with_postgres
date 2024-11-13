# ACL with Postgres

*(Most of the project is generated with Cline + Claude and manually revised)*

The goal of the project is an ACL system fully packed inside a Postgres database.

## Design

### Hierachical
Permissions are in tree structure like `manage`, `manage/create`. When assigned with only `manage`: true, all `manage/**` permissions are considered true unless otherwise specified. 

### Role-based
Permissions are assigned to roles. Roles are assigned to users. Users can also be assigned with individual permissions that take priority over role permissions.

### Scopes
Multiple permissions with same name can be assigned to users/roles given different scopes. For example `manage` with scope 123 represents rights to manage resource#123. Scope values are external, they are meaningless to this acl system and only serve as identifiers.

### Built-in Cache
The result of query for (user_id, permission, scope) is cached to an unlogged table. Cached rows are outdated after 1 hour, or updated on change in related upstream rows. The cached rows are not getting deleted by the system, `pg_cron` may be required to clean the table.

### Partitioned
Role permissions, User permissions and the cache tables are partitioned by permission name to minimize overhead with high amount of roles and users.

## Usage

#### check_permission(p_user_id BIGINT, p_permission TEXT, p_scope BIGINT)

#### check_permission_cached (p_user_id BIGINT, p_permission TEXT, p_scope BIGINT)

## Tests

PgTap tests are performed with [PgTap](https://pgtap.org).

To run the tests with PgTap installed, query `SELECT * FROM runtests('pgtap_test_acl');`.

For details of tests please refer to `pgtap_acl.pgsql`.