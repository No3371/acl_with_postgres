# ACL with Postgres

*(Most of the project is generated with Cline + Claude and manually revised)*

The goal of the project is an ACL system fully packed inside a Postgres database.

## Design

### Hierachical
Permissions are structured like "manage", "manage/create" with default value and inheritance.

### Role-based
Permissions are assigned to roles. Roles are assigned to users. Users can also be assigned with individual permissions that take priority over role permissions.

### Scopes
Multiple permissions with same name can be assigned to users/roles given different scopes. For example "manage" with scope 123 represents rights to manage asset#123.

### Built-in Cache
The result of query for (user_id, permission, scope) is cached to an unlogged table. Cached rows are outdated after 1 hour or any change in related upstream rows.

### Partitioned
Role permissions, User permissions and the cache tables are partitioned by permission to minimize overhead with high amount of roles and users.