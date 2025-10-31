SET search_path = acl;

DROP TABLE IF EXISTS perm_tree CASCADE;
CREATE TABLE perm_tree (
    perm_id BIGINT PRIMARY KEY,
    parent_perm_id BIGINT, CHECK (parent_perm_id is distinct from perm_id)
);

DROP TABLE IF EXISTS perm_upstream CASCADE;
CREATE TABLE perm_upstream (
    perm_id BIGINT PRIMARY KEY,
    upstream_perm_ids BIGINT[] NOT NULL-- this includes this perm_id
);

DROP TABLE IF EXISTS perm_downstream CASCADE;
CREATE TABLE perm_downstream (
    perm_id BIGINT PRIMARY KEY,
    downstream_perm_ids BIGINT[] NOT NULL-- this includes this perm_id
);

-- Function to find parent permission ID
CREATE OR REPLACE FUNCTION find_parent_perm_id(p_permission TEXT) 
RETURNS BIGINT AS $$
DECLARE
    parent_perm TEXT;
BEGIN
    parent_perm := LEFT(p_permission, LENGTH(p_permission) - STRPOS(REVERSE(p_permission), '/'));
    IF parent_perm = $1 THEN -- no slash
        RETURN NULL;
    END IF;
    
    RETURN (SELECT perm_id FROM perm WHERE permission = parent_perm);
END;
$$ LANGUAGE plpgsql;

-- Function to rebuild the entire permission tree
CREATE OR REPLACE FUNCTION rebuild_perm_tree() 
RETURNS VOID AS $$
BEGIN
    -- Clear the existing tree
    DELETE FROM perm_tree;
    
    -- Rebuild the tree for all permissions
    INSERT INTO perm_tree (perm_id, parent_perm_id)
    SELECT 
        p.perm_id,
        find_parent_perm_id(p.permission)
    FROM perm p;

    DELETE FROM perm_upstream;
    INSERT INTO perm_upstream (perm_id, upstream_perm_ids)
    SELECT
        p.perm_id,
        (SELECT ARRAY_AGG(perm_id ORDER BY depth ASC) FROM find_perm_ancestors_inclusive(p.perm_id) AS fpa)
    FROM perm p;

    DELETE FROM perm_downstream;
    INSERT INTO perm_downstream (perm_id, downstream_perm_ids)
    SELECT
        p.perm_id,
        (SELECT ARRAY_AGG(perm_id ORDER BY depth ASC) FROM find_perm_descendants_inclusive(p.perm_id) AS fpd)
    FROM perm p;
END;
$$ LANGUAGE plpgsql;

-- Trigger function that calls rebuild_perm_tree
CREATE OR REPLACE FUNCTION trigger_rebuild_perm_tree()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM rebuild_perm_tree();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
DROP TRIGGER IF EXISTS rebuild_perm_tree_trigger ON perm;
CREATE TRIGGER rebuild_perm_tree_trigger
    AFTER INSERT OR DELETE ON perm
    FOR EACH STATEMENT
    EXECUTE FUNCTION trigger_rebuild_perm_tree();

CREATE OR REPLACE FUNCTION prevent_perm_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Permissions are suppoesd to be immutable to prevent hierachy corruption. Delete and Insert instead.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_perm_update_trigger
    BEFORE UPDATE ON perm
    FOR EACH STATEMENT
    EXECUTE FUNCTION prevent_perm_update();


-- Function to get all children
-- ORDER BY depth ASC is required to traverse in the correct order when selecting from the returned table
CREATE FUNCTION find_perm_descendants_inclusive(p_perm_id BIGINT)
RETURNS TABLE(perm_id BIGINT, parent_perm_id BIGINT, depth INT) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE children AS (
        SELECT pt.perm_id, pt.parent_perm_id, 0 AS depth
        FROM perm_tree pt
        WHERE pt.perm_id = p_perm_id
        
        UNION ALL
        
        SELECT pt.perm_id, pt.parent_perm_id, c.depth + 1
        FROM perm_tree pt
        INNER JOIN children c ON pt.parent_perm_id = c.perm_id
    )
    SELECT * FROM children;
END;
$$ LANGUAGE plpgsql;

-- Function to get all parents
-- ORDER BY depth ASC is required to traverse in the correct order when selecting from the returned table
CREATE FUNCTION find_perm_ancestors_inclusive(p_perm_id BIGINT)
RETURNS TABLE(perm_id BIGINT, parent_perm_id BIGINT, depth INT) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE parents AS (
        SELECT pt.perm_id, pt.parent_perm_id, 0 AS depth
        FROM perm_tree pt
        WHERE pt.perm_id = p_perm_id
        
        UNION ALL
        
        SELECT pt.perm_id, pt.parent_perm_id, p.depth + 1
        FROM perm_tree pt
        INNER JOIN parents p ON pt.perm_id = p.parent_perm_id
    )
    SELECT * FROM parents;
END;
$$ LANGUAGE plpgsql;