## `check_permission_cached(user_id BIGINT, scope BIGINT, permission TEXT, ttl_seconds BIGINT DEFAULT 3600)`
Returns resolved-and-cached permission for the user and the scope. If the permission for the scope is not cached, automatically calls check_permission(...) and cache the value before returning it.

## `check_permission(user_id BIGINT, scope BIGINT, permission TEXT)`
Resolve the permission assigned to the user for the scope.
Permissions are resolved hierachically, for example when checking `user/create`, it first trys to get the state of `user/create` assigned to the user, and returns it if it's found, or it moves on to check the state of `user` assigned to the user.

In other words, if a child permission is not assigned, it'd be covered by the first upstream permission found to be assigned.

The system also allows you to assign permissions to individual users or to roles. Roles are basically pre-defined permission groups that can be assigned to users.

When checking permission for a user, it first checks if the user is assigned with the specified permission, if so, it just returns the state of the assigned permission; Otherwise it trys to gets the permission state from the role assigned with the permission with the highest priorty assigned to the user.

Additionally, permissions can be scoped. Scopes are just identifiers, you can have multiple identical permissions assigned with different scope values. The simplist way to use scope is use it to differentiate resources you want to have access control over.

There's no function designed for writing permissions, in order to make changes you just INSERT or UPDATE these tables: `perm`, `user`, `role`, `role_perm`, `user_perm`, `user_role`. Noted that you can not assign permissions with `NULL` state; on the other hand, when you get a `NULL` when you check for permission, you can be sure it means not assigned.

Overall, this is inspired by and very similar to Discord's permission model. The core difference is Discord associates resource directly with users/roles, therefore (I assume) the permission lookup starts with associated users/roles, in other words, Discord's permission is scoped at user/role level.