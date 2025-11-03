-- Initialize ACL tables and functions

CREATE TABLE acl.acl_perm (
    acl_perm_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    permission TEXT NOT NULL CHECK (permission <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (permission)
);

CREATE TABLE acl."acl_user" (
    acl_user_id BIGINT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE acl."acl_role" (
    acl_role_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    role_name TEXT NOT NULL,
    priority INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE acl.acl_role_perm (
    acl_role_id BIGINT NOT NULL REFERENCES acl."acl_role"(acl_role_id) ON DELETE CASCADE,
    scope BIGINT,
    acl_perm_id BIGINT NOT NULL REFERENCES acl."acl_perm"(acl_perm_id) ON DELETE CASCADE,
    "state" BOOLEAN,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (acl_role_id, scope, acl_perm_id)
);

CREATE INDEX ON acl.acl_role_perm (scope, acl_perm_id);

CREATE TABLE acl.acl_user_perm (
    acl_user_id BIGINT NOT NULL REFERENCES acl."acl_user"(acl_user_id) ON DELETE CASCADE,
    scope BIGINT,
    acl_perm_id BIGINT NOT NULL REFERENCES acl."acl_perm"(acl_perm_id) ON DELETE CASCADE,
    "state" BOOLEAN,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (acl_user_id, scope, acl_perm_id)
);

CREATE INDEX ON acl.acl_user_perm (scope, acl_perm_id);

CREATE TABLE acl.acl_user_role (
    acl_user_id BIGINT NOT NULL REFERENCES acl."acl_user"(acl_user_id) ON DELETE CASCADE,
    acl_role_id BIGINT NOT NULL REFERENCES acl."acl_role"(acl_role_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (acl_user_id, acl_role_id)
);

CREATE INDEX ON acl.acl_user_role (acl_role_id);

CREATE FUNCTION acl.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON acl.acl_perm
FOR EACH ROW
EXECUTE FUNCTION acl.update_updated_at();

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON acl.acl_role
FOR EACH ROW
EXECUTE FUNCTION acl.update_updated_at();

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON acl.acl_user_perm
FOR EACH ROW
EXECUTE FUNCTION acl.update_updated_at();

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON acl.acl_role_perm
FOR EACH ROW
EXECUTE FUNCTION acl.update_updated_at();

CREATE OR REPLACE FUNCTION acl.acl_check_perm(
    p_user_id BIGINT,
    p_scope BIGINT,
    p_permission TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    active_id BIGINT;
    upstream_perm_ids BIGINT[];
    v_result BOOLEAN;
BEGIN
    SELECT acl_perm_upstream.upstream_perm_ids
    INTO upstream_perm_ids
    FROM acl.acl_perm JOIN acl.acl_perm_upstream ON acl.acl_perm.acl_perm_id = acl.acl_perm_upstream.acl_perm_id
    WHERE acl.acl_perm.permission = p_permission;

    FOREACH active_id IN ARRAY upstream_perm_ids LOOP   
        SELECT "state" INTO v_result
        FROM acl.acl_user_perm
        WHERE acl_user_id = p_user_id
          AND scope = p_scope
          AND acl_perm_id = active_id;
        
        IF v_result IS NOT NULL THEN
            RETURN v_result;
        END IF;
    END LOOP;
    
    -- Then check role permissions in order of priority
    FOREACH active_id IN ARRAY upstream_perm_ids LOOP           
        SELECT rp.state INTO v_result
        FROM acl.acl_role_perm rp
        JOIN acl.acl_perm p ON p.acl_perm_id = rp.acl_perm_id
        JOIN acl.acl_role r ON r.acl_role_id = rp.acl_role_id
        JOIN acl.acl_user_role ur ON ur.acl_role_id = r.acl_role_id
        WHERE ur.acl_user_id = p_user_id
          AND rp.scope = p_scope
          AND p.acl_perm_id = active_id
        ORDER BY r.priority DESC
        LIMIT 1;
        
        IF v_result IS NOT NULL THEN
            RETURN v_result;
        END IF;
    END LOOP;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER;

CREATE OR REPLACE FUNCTION acl.acl_get_perm_id (permission TEXT)
    RETURNS BIGINT
    LANGUAGE SQL
BEGIN ATOMIC
    RETURN (SELECT acl_perm_id FROM acl.acl_perm WHERE permission = $1);
END;

CREATE OR REPLACE FUNCTION acl.acl_get_role_id (role_name TEXT)
    RETURNS BIGINT
    LANGUAGE SQL
BEGIN ATOMIC
    RETURN (SELECT acl_role_id FROM acl.acl_role WHERE role_name = $1);
END;