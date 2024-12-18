# ACL with Postgres

*(Most of the project is generated with Cline + Claude and manually revised)*

The goal of the project is an ACL system fully packed inside a Postgres database.

## Design

### Hierachical
Permissions are in tree structure like `manage`, `manage/create`. When assigned with only `manage`: true, all `manage/**` permissions are considered true unless otherwise specified; When a permission is not assigned or assgined with NULL, parent permission value is used. By default, unassigned permissions or ones without a parent are considered false.

### Role-based
Permissions are assigned to roles. Roles are assigned to users. Users can also be assigned with individual permissions that take priority over role permissions.

### Scopes
Multiple permissions with same name can be assigned to users/roles given different scopes. For example `manage` with scope 123 represents rights to manage resource#123. Scope values are external, they are meaningless to this acl system and only serve as identifiers.

### Built-in Cache
The result of query for (user_id, permission, scope) is cached to an unlogged table. Cached rows are outdated after 1 hour, or updated on change in related upstream rows. The cached rows are not getting deleted by the system, `pg_cron` may be required to clean the table.

### Partitioned
Role permissions, User permissions and the cache tables are partitioned by permission name to minimize overhead with high amount of roles and users.

## Usage

### Idiomatic Example
![image](https://github.com/user-attachments/assets/58f6f2b3-0194-433e-a09a-f8b9a440c970)

### Functions

#### check_permission(p_user_id BIGINT, p_permission TEXT, p_scope BIGINT)

The function performs hierachy lookup to determine whether the user owns the permission. It first checks individual permissions assigned to the user, then checks permissions come with assigned roles.

If a child permission is not assigned or assigned with NULL, it'll check against parent permission until a value is found or reaching the hierachy root.

#### check_permission_cached (p_user_id BIGINT, p_permission TEXT, p_scope BIGINT)

This function wraps around `check_permission` automatically caches the result. Built-in cache can be entirely skipped by avoiding this function.

### Tables

#### user(user_id BIGINT)

INSERT/UPDATE/DELETE against this table to manage users.

#### role(role_name TEXT, priority INT)

INSERT/UPDATE/DELETE against this table to manage roles.

#### perm(permission TEXT)

INSERT/DELETE against this table to manage permissions. UPDATE is not allowed to prevent un-expected hierachy change.

Upon any change, `perm_tree` table is rebuilt. Permission hierachy is solely determined by the "permission" column. For example, All permission named `manage/*` are always children of `manage`.

#### user_role(user_id BIGINT, role_id BIGINT)

INSERT/UPDATE/DELETE against this table to assign roles to users.

#### role_perm(role_id BIGINT, perm_id BIGINT, scope BIGINT, state BOOLEAN)

INSERT/UPDATE/DELETE against this table to assign permissions to roles.

#### user_perm(user_id BIGINT, perm_id BIGINT, scope BIGINT, state BOOLEAN)

INSERT/UPDATE/DELETE against this table to assign individual permissions to users. User permissions take priority over role permissions.


## PostgREST

The system is supposed to be used internally. It can be paired with [PostgREST](https://github.com/PostgREST/postgrest) to be served as an independent RESTful service.

Executing statements from `init_postgrest.pgsql` will prepare the `acl` schema, all functions and most of the tables to be accessible by a nologin user `web_anon`.

NOTE: To make this works, all the init statements must be performed in `acl` schema.

## Tests

Unit tests are performed with [PgTap](https://pgtap.org).

To run the tests with PgTap installed, query `SELECT * FROM runtests('pgtap_test_acl');`.

For details of tests please refer to `pgtap_acl.pgsql`.
