CREATE TABLE "perm" (
    perm_id BIGSERIAL PRIMARY KEY,
    permission TEXT NOT NULL,
    default_state BOOLEAN DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  	UNIQUE (permission)
);

CREATE TABLE "user" (
    user_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE "role" (
    role_id BIGSERIAL PRIMARY KEY,
    role_name TEXT NOT NULL,
    priority INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS role_perm CASCADE;
DROP TABLE IF EXISTS user_perm CASCADE;

CREATE TABLE "role_perm" (
    role_id BIGINT NOT NULL REFERENCES "role"(role_id) ON DELETE RESTRICT,
    perm_id BIGINT NOT NULL REFERENCES "perm"(perm_id) ON DELETE RESTRICT,
    scope BIGINT NOT NULL,
    state BOOLEAN DEFAULT NULL,
    assigned_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (role_id, perm_id, scope)
) PARTITION BY LIST (perm_id);

CREATE TABLE "user_perm" (
    user_id BIGINT NOT NULL REFERENCES "user"(user_id) ON DELETE RESTRICT,
    perm_id BIGINT NOT NULL REFERENCES "perm"(perm_id) ON DELETE RESTRICT,
    scope BIGINT NOT NULL,
    state BOOLEAN DEFAULT NULL,
    assigned_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, perm_id, scope)
) PARTITION BY LIST (perm_id);

CREATE TABLE "user_role" (
    user_id BIGINT NOT NULL REFERENCES "user"(user_id) ON DELETE RESTRICT,
    role_id BIGINT NOT NULL REFERENCES "role"(role_id) ON DELETE RESTRICT,
    assigned_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role_id)
);

CREATE OR REPLACE FUNCTION check_permission(
    p_user_id BIGINT,
    p_permission TEXT,
    p_scope BIGINT
) RETURNS BOOLEAN AS $$
DECLARE
    v_result BOOLEAN;
    v_perm_parts TEXT[];
    v_partial_perm TEXT;
    i INTEGER;
BEGIN
    -- First check direct user permissions at all permission levels
    v_perm_parts := string_to_array(p_permission, '/');
    v_partial_perm := p_permission;
    
    FOR i IN REVERSE array_length(v_perm_parts, 1)..1 LOOP
        
        SELECT state INTO v_result
        FROM user_perm up
        JOIN perm p ON p.perm_id = up.perm_id
        WHERE up.user_id = p_user_id
          AND p.permission = v_partial_perm
          AND up.scope = p_scope;
        
        IF v_result IS NOT NULL THEN
            RETURN v_result;
        END IF;

        IF i > 1 THEN
            v_partial_perm := substring(v_partial_perm, 1, char_length(v_partial_perm) - char_length(v_perm_parts[i]) - 1);
        END IF;
    END LOOP;
    
    v_partial_perm := p_permission;
    -- Then check role permissions in order of priority
    FOR i IN REVERSE array_length(v_perm_parts, 1)..1 LOOP
        
        SELECT rp.state INTO v_result
        FROM role_perm rp
        JOIN perm p ON p.perm_id = rp.perm_id
        JOIN role r ON r.role_id = rp.role_id
        JOIN user_role ur ON ur.role_id = r.role_id
        WHERE ur.user_id = p_user_id
        AND p.permission = v_partial_perm
        AND rp.scope = p_scope
        ORDER BY r.priority DESC
        LIMIT 1;
        
        IF v_result IS NOT NULL THEN
            RETURN v_result;
        END IF;

        IF i > 1 THEN
            v_partial_perm := substring(v_partial_perm, 1, char_length(v_partial_perm) - char_length(v_perm_parts[i]) - 1);
        END IF;
    END LOOP;
    
    -- If no explicit permission found, return the default state from the most specific permission
    SELECT p.default_state INTO v_result
    FROM perm p
    WHERE p.permission = p_permission;
    
    RETURN COALESCE(v_result, FALSE);
END;
$$ LANGUAGE plpgsql;
