CREATE TABLE "perm" (
    perm_id BIGSERIAL PRIMARY KEY,
    permission TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (permission)
);

CREATE TABLE "user" (
    user_id BIGINT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
)

CREATE TABLE "role" (
    role_id BIGSERIAL PRIMARY KEY,
    role_name TEXT NOT NULL,
    priority INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
)

DROP TABLE IF EXISTS role_perm CASCADE;
DROP TABLE IF EXISTS user_perm CASCADE;

CREATE TABLE "role_perm" (
    role_id BIGINT NOT NULL REFERENCES "role"(role_id) ON DELETE CASCADE,
    scope BIGINT NOT NULL,
    perm_id BIGINT NOT NULL REFERENCES "perm"(perm_id) ON DELETE CASCADE,
    state BOOLEAN DEFAULT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (role_id, scope, perm_id)
)

CREATE TABLE "user_perm" (
    user_id BIGINT NOT NULL REFERENCES "user"(user_id) ON DELETE CASCADE,
    scope BIGINT NOT NULL,
    perm_id BIGINT NOT NULL REFERENCES "perm"(perm_id) ON DELETE CASCADE,
    state BOOLEAN DEFAULT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, scope, perm_id)
)

CREATE TABLE "user_role" (
    user_id BIGINT NOT NULL REFERENCES "user"(user_id) ON DELETE CASCADE,
    role_id BIGINT NOT NULL REFERENCES "role"(role_id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role_id)
);

CREATE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_updated_at_trigger
BEFORE UPDATE ON "perm"
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
    p_permission TEXT,
    default_state BOOLEAN
) RETURNS BOOLEAN AS $$
DECLARE
    target RECORD;
    v_result BOOLEAN;
    target_perm TEXT;
    i INTEGER;
BEGIN
    target := (SELECT perm.perm_id, perm.permission, perm_tree.parent_perm_id
               FROM perm JOIN perm_tree ON perm.perm_id = perm_tree.perm_id
               WHERE permission = p_permission);   
    target_perm := p_permission;
    v_result := default_state;

    WHILE target IS NOT NULL LOOP   
        SELECT state INTO v_result
        FROM user_perm up
        JOIN perm p ON p.perm_id = up.perm_id
        WHERE up.user_id = p_user_id
          AND up.scope = p_scope;
          AND p.perm_id = target.perm_id;
        
        IF v_result IS NOT NULL THEN
            RETURN v_result;
        END IF;

        target_perm := LEFT(target_perm, LENGTH(target_perm) - STRPOS(REVERSE(target_perm), '/'));
        target := (SELECT perm.perm_id, perm.permission, perm_tree.parent_perm_id
                   FROM perm JOIN perm_tree ON perm.perm_id = perm_tree.perm_id
                   WHERE permission = target_perm);
    END LOOP;
    
    target_perm := p_permission;
    -- Then check role permissions in order of priority
    FOR i IN REVERSE array_length(v_perm_parts, 1)..1 LOOP
        
        SELECT rp.state INTO v_result
        FROM role_perm rp
        JOIN perm p ON p.perm_id = rp.perm_id
        JOIN "role" r ON r.role_id = rp.role_id
        JOIN user_role ur ON ur.role_id = r.role_id
        WHERE ur.user_id = p_user_id
        AND rp.scope = p_scope
        AND p.perm_id = target.perm_id
        ORDER BY r.priority DESC
        LIMIT 1;
        
        IF v_result IS NOT NULL THEN
            RETURN v_result;
        END IF;

        target_perm := LEFT(target_perm, LENGTH(target_perm) - STRPOS(REVERSE(target_perm), '/'));
        target := (SELECT perm.perm_id, perm.permission, perm_tree.parent_perm_id
                   FROM perm JOIN perm_tree ON perm.perm_id = perm_tree.perm_id
                   WHERE permission = target_perm);
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
