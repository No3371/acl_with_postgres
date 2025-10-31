SET search_path = acl;

DROP TABLE IF EXISTS "perm_cache";
-- Create unlogged cache table
CREATE TABLE "perm_cache" (
    user_id BIGINT NOT NULL,
    scope BIGINT NOT NULL,
    permission TEXT NOT NULL,
    perm_id BIGINT NOT NULL,
    state BOOLEAN,
    cached_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, scope, permission)
);

CREATE INDEX ON perm_cache (user_id, scope, perm_id);
CREATE INDEX ON perm_cache (perm_id);
CREATE INDEX ON perm_cache (cached_at);

-- Function to clear expired cache entries
CREATE OR REPLACE FUNCTION clear_expired_cache(p_cache_ttl_seconds BIGINT DEFAULT 3600) RETURNS VOID AS $$
BEGIN
    DELETE FROM perm_cache 
    WHERE cached_at < NOW() - make_interval(secs => p_cache_ttl_seconds);
END;
$$ LANGUAGE plpgsql;

-- Function to clear cache for specific user and permission
CREATE OR REPLACE FUNCTION clear_user_perm_cache(p_user_id BIGINT, p_scope BIGINT DEFAULT NULL, p_permission TEXT DEFAULT NULL) 
RETURNS VOID AS $$
DECLARE
    v_perm_id BIGINT;
BEGIN
    v_perm_id := (SELECT get_perm_id(p_permission));
    IF p_permission IS NULL THEN
        IF p_scope IS NULL THEN
            DELETE FROM perm_cache WHERE user_id = p_user_id;
        ELSE
            DELETE FROM perm_cache WHERE user_id = p_user_id AND scope = p_scope;
        END IF;
    ELSE
        IF p_scope IS NULL THEN
            DELETE FROM perm_cache
            WHERE user_id = p_user_id
              AND perm_id = ANY((SELECT downstream_perm_ids FROM perm_downstream WHERE perm_id = v_perm_id)::BIGINT[]);
        ELSE
            DELETE FROM perm_cache
            WHERE user_id = p_user_id
              AND scope = p_scope
              AND perm_id = ANY((SELECT downstream_perm_ids FROM perm_downstream WHERE perm_id = v_perm_id)::BIGINT[]);
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- This finds all users assigned to the role and clears the cache of all downstream permissions of the permission in question for them
CREATE OR REPLACE FUNCTION clear_role_perm_cache(p_role_id BIGINT, p_scope BIGINT, p_permission TEXT) 
RETURNS VOID AS $$
DECLARE
    v_downstream_perm_ids BIGINT[];
BEGIN
    IF p_permission IS NULL THEN
        RAISE EXCEPTION 'clear_role_perm_cache: p_permission cannot be NULL';
    END IF;

    SELECT downstream_perm_ids INTO v_downstream_perm_ids
    FROM perm_downstream
    WHERE perm_id = (SELECT get_perm_id(p_permission));

    WITH ru AS (
        SELECT user_id
        FROM user_role
        WHERE role_id = p_role_id
    )
    DELETE FROM perm_cache 
    USING ru
    WHERE perm_cache.user_id = ru.user_id
      AND perm_cache.scope = p_scope
      AND perm_cache.perm_id = ANY(v_downstream_perm_ids);
END;
$$ LANGUAGE plpgsql;

-- Trigger function for user_perm changes
CREATE OR REPLACE FUNCTION trigger_clear_user_perm_cache()
RETURNS TRIGGER AS $$
DECLARE
    v_permission TEXT;
BEGIN
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        SELECT permission INTO v_permission FROM perm WHERE perm_id = OLD.perm_id;
        PERFORM clear_user_perm_cache(OLD.user_id, OLD.scope, v_permission);
    END IF;
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        SELECT permission INTO v_permission FROM perm WHERE perm_id = NEW.perm_id;
        PERFORM clear_user_perm_cache(NEW.user_id, NEW.scope, v_permission);
    END IF;   
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger function for role_perm changes
CREATE OR REPLACE FUNCTION trigger_clear_role_perm_cache()
RETURNS TRIGGER AS $$
DECLARE
    v_permission TEXT;
BEGIN
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        SELECT permission INTO v_permission FROM perm WHERE perm_id = OLD.perm_id;
        PERFORM clear_role_perm_cache(OLD.role_id, OLD.scope, v_permission);
    END IF;
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        SELECT permission INTO v_permission FROM perm WHERE perm_id = NEW.perm_id;
        PERFORM clear_role_perm_cache(NEW.role_id, NEW.scope, v_permission);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger function for user_role changes
-- This finds all permissions assigned to the role and clears the cache for the user
CREATE OR REPLACE FUNCTION trigger_clear_user_role_cache()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        WITH rp AS (
            SELECT scope, perm_id
            FROM role_perm
            WHERE role_id = OLD.role_id
        )
        DELETE FROM perm_cache 
        USING rp
            JOIN perm_downstream pd ON pd.perm_id = rp.perm_id
        WHERE perm_cache.user_id = OLD.user_id
          AND perm_cache.scope = rp.scope
          AND perm_cache.perm_id = ANY(pd.downstream_perm_ids);
    END IF;
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        WITH rp AS (
            SELECT scope, perm_id
            FROM role_perm
            WHERE role_id = NEW.role_id
        )
        DELETE FROM perm_cache 
        USING rp
            JOIN perm_downstream pd ON pd.perm_id = rp.perm_id
        WHERE perm_cache.user_id = NEW.user_id
          AND perm_cache.scope = rp.scope
          AND perm_cache.perm_id = ANY(pd.downstream_perm_ids);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger function for perm_tree changes
CREATE OR REPLACE FUNCTION trigger_clear_all_perm_cache()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM perm_cache;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
DROP TRIGGER IF EXISTS clear_all_perm_cache ON perm_tree;
CREATE TRIGGER clear_all_perm_cache_on_perm_tree_change
    AFTER INSERT OR UPDATE OR DELETE ON perm
    FOR EACH ROW
    EXECUTE FUNCTION trigger_clear_all_perm_cache();

DROP TRIGGER IF EXISTS clear_user_perm_cache ON user_perm;
CREATE TRIGGER clear_user_perm_cache
    AFTER INSERT OR UPDATE OR DELETE ON user_perm
    FOR EACH ROW
    EXECUTE FUNCTION trigger_clear_user_perm_cache();

DROP TRIGGER IF EXISTS clear_role_perm_cache ON role_perm;
CREATE TRIGGER clear_role_perm_cache
    AFTER INSERT OR UPDATE OR DELETE ON role_perm
    FOR EACH ROW
    EXECUTE FUNCTION trigger_clear_role_perm_cache();

DROP TRIGGER IF EXISTS clear_user_role_cache ON user_role;
CREATE TRIGGER clear_user_role_cache
    AFTER INSERT OR UPDATE OR DELETE ON user_role
    FOR EACH ROW
    EXECUTE FUNCTION trigger_clear_user_role_cache();

CREATE OR REPLACE FUNCTION check_perm_cached(
    p_user_id BIGINT,
    p_scope BIGINT,
    p_permission TEXT,
    p_cache_ttl_seconds BIGINT DEFAULT 3600
) RETURNS BOOLEAN AS $$
DECLARE
    v_perm_id BIGINT;
    v_state BOOLEAN;
    v_cached_state BOOLEAN;
BEGIN
    -- Check cache first
    SELECT "state" INTO v_cached_state
    FROM perm_cache
    WHERE user_id = p_user_id
      AND scope = p_scope
      AND permission = p_permission
      AND cached_at > NOW() - make_interval(secs => p_cache_ttl_seconds);
      
    IF v_cached_state IS NOT NULL THEN
        RETURN v_cached_state;
    END IF;

    SELECT check_permission(p_user_id, p_scope, p_permission) INTO v_state;
    
    -- Cache and return final state
    INSERT INTO perm_cache (user_id, scope, permission, "state", perm_id)
    VALUES (p_user_id, p_scope, p_permission, v_state, (SELECT get_perm_id(p_permission)))
    ON CONFLICT (user_id, scope, permission)
    DO UPDATE SET "state" = v_state, cached_at = NOW(), perm_id = (SELECT get_perm_id(p_permission));
    
    RETURN v_state;
END;
$$ LANGUAGE plpgsql;
