SET search_path = acl;

CREATE TABLE perm (
    perm_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    permission TEXT NOT NULL CHECK (permission <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (permission)
);

CREATE TABLE "user" (
    user_id BIGINT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "role" (
    role_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    role_name TEXT NOT NULL,
    priority INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE role_perm (
    role_id BIGINT NOT NULL REFERENCES "role"(role_id) ON DELETE CASCADE,
    scope BIGINT,
    perm_id BIGINT NOT NULL REFERENCES "perm"(perm_id) ON DELETE CASCADE,
    "state" BOOLEAN,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (role_id, scope, perm_id)
);

CREATE INDEX ON role_perm (scope, perm_id);

CREATE TABLE user_perm (
    user_id BIGINT NOT NULL REFERENCES "user"(user_id) ON DELETE CASCADE,
    scope BIGINT,
    perm_id BIGINT NOT NULL REFERENCES "perm"(perm_id) ON DELETE CASCADE,
    "state" BOOLEAN,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, scope, perm_id)
);

CREATE INDEX ON user_perm (scope, perm_id);

CREATE TABLE user_role (
    user_id BIGINT NOT NULL REFERENCES "user"(user_id) ON DELETE CASCADE,
    role_id BIGINT NOT NULL REFERENCES "role"(role_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX ON user_role (role_id);

CREATE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON perm
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON "role"
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON user_perm
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON "role_perm"
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

CREATE OR REPLACE FUNCTION check_permission(
    p_user_id BIGINT,
    p_scope BIGINT,
    p_permission TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    active_id BIGINT;
    upstream_perm_ids BIGINT[];
    v_result BOOLEAN;
BEGIN
    SELECT perm_upstream.upstream_perm_ids
    INTO upstream_perm_ids
    FROM perm JOIN perm_upstream ON perm.perm_id = perm_upstream.perm_id
    WHERE perm.permission = p_permission;

    FOREACH active_id IN ARRAY upstream_perm_ids LOOP   
        SELECT "state" INTO v_result
        FROM user_perm
        WHERE user_id = p_user_id
          AND scope = p_scope
          AND perm_id = active_id;
        
        IF v_result IS NOT NULL THEN
            RETURN v_result;
        END IF;
    END LOOP;
    
    -- Then check role permissions in order of priority
    FOREACH active_id IN ARRAY upstream_perm_ids LOOP           
        SELECT rp.state INTO v_result
        FROM role_perm rp
        JOIN perm p ON p.perm_id = rp.perm_id
        JOIN "role" r ON r.role_id = rp.role_id
        JOIN user_role ur ON ur.role_id = r.role_id
        WHERE ur.user_id = p_user_id
          AND rp.scope = p_scope
          AND p.perm_id = active_id
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

CREATE OR REPLACE FUNCTION get_perm_id (permission TEXT)
    RETURNS BIGINT
    LANGUAGE SQL
BEGIN ATOMIC
    RETURN (SELECT perm_id FROM perm WHERE permission = $1);
END;

CREATE OR REPLACE FUNCTION get_role_id (role_name TEXT)
    RETURNS BIGINT
    LANGUAGE SQL
BEGIN ATOMIC
    RETURN (SELECT role_id FROM "role" WHERE role_name = $1);
END;