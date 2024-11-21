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
) PARTITION BY HASH (user_id);

-- Create 10 partitions for user table (0-9)
CREATE TABLE user_p0 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 0);
CREATE TABLE user_p1 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 1);
CREATE TABLE user_p2 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 2);
CREATE TABLE user_p3 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 3);
CREATE TABLE user_p4 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 4);
CREATE TABLE user_p5 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 5);
CREATE TABLE user_p6 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 6);
CREATE TABLE user_p7 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 7);
CREATE TABLE user_p8 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 8);
CREATE TABLE user_p9 PARTITION OF "user" FOR VALUES WITH (modulus 10, remainder 9);

CREATE TABLE "role" (
    role_id BIGSERIAL PRIMARY KEY,
    role_name TEXT NOT NULL,
    priority INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
) PARTITION BY HASH (role_id);

-- Create 10 partitions for role table (0-9)
CREATE TABLE role_p0 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 0);
CREATE TABLE role_p1 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 1);
CREATE TABLE role_p2 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 2);
CREATE TABLE role_p3 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 3);
CREATE TABLE role_p4 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 4);
CREATE TABLE role_p5 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 5);
CREATE TABLE role_p6 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 6);
CREATE TABLE role_p7 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 7);
CREATE TABLE role_p8 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 8);
CREATE TABLE role_p9 PARTITION OF "role" FOR VALUES WITH (modulus 10, remainder 9);

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
    
    RETURN COALESCE(v_result, FALSE);
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
