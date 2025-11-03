

DROP TABLE IF EXISTS acl.acl_perm_tree CASCADE;
CREATE TABLE acl.acl_perm_tree (
    acl_perm_id BIGINT PRIMARY KEY,
    parent_perm_id BIGINT, CHECK (parent_perm_id is distinct from acl_perm_id)
);

DROP TABLE IF EXISTS acl.acl_perm_upstream CASCADE;
CREATE TABLE acl.acl_perm_upstream (
    acl_perm_id BIGINT PRIMARY KEY,
    upstream_perm_ids BIGINT[] NOT NULL-- this includes this acl_perm_id
);

DROP TABLE IF EXISTS acl.acl_perm_downstream CASCADE;
CREATE TABLE acl.acl_perm_downstream (
    acl_perm_id BIGINT PRIMARY KEY,
    downstream_perm_ids BIGINT[] NOT NULL-- this includes this acl_perm_id
);

-- Function to find parent permission ID
CREATE OR REPLACE FUNCTION acl.acl_find_parent_perm_id(p_permission TEXT) 
RETURNS BIGINT AS $$
DECLARE
    parent_perm TEXT;
BEGIN
    parent_perm := LEFT(p_permission, LENGTH(p_permission) - STRPOS(REVERSE(p_permission), '/'));
    IF parent_perm = $1 THEN -- no slash
        RETURN NULL;
    END IF;
    
    RETURN (SELECT acl_perm_id FROM acl.acl_perm WHERE permission = parent_perm);
END;
$$ LANGUAGE plpgsql;

-- Function to rebuild the entire permission tree
CREATE OR REPLACE FUNCTION acl.acl_rebuild_perm_tree() 
RETURNS VOID AS $$
BEGIN
    -- Clear the existing tree
    DELETE FROM acl.acl_perm_tree;
    
    -- Rebuild the tree for all permissions
    INSERT INTO acl.acl_perm_tree (acl_perm_id, parent_perm_id)
    SELECT 
        p.acl_perm_id,
        acl.acl_find_parent_perm_id(p.permission)
    FROM acl.acl_perm p;

    DELETE FROM acl.acl_perm_upstream;
    INSERT INTO acl.acl_perm_upstream (acl_perm_id, upstream_perm_ids)
    SELECT
        p.acl_perm_id,
        (SELECT ARRAY_AGG(acl_perm_id ORDER BY depth ASC) FROM acl.acl_find_perm_ancestors_inclusive(p.acl_perm_id) AS fpa)
    FROM acl.acl_perm p;

    DELETE FROM acl.acl_perm_downstream;
    INSERT INTO acl.acl_perm_downstream (acl_perm_id, downstream_perm_ids)
    SELECT
        p.acl_perm_id,
        (SELECT ARRAY_AGG(acl_perm_id ORDER BY depth ASC) FROM acl.acl_find_perm_descendants_inclusive(p.acl_perm_id) AS fpd)
    FROM acl.acl_perm p;
END;
$$ LANGUAGE plpgsql;

-- Trigger function that calls acl_rebuild_perm_tree
CREATE OR REPLACE FUNCTION acl.trigger_acl_rebuild_perm_tree()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM acl.acl_rebuild_perm_tree();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
DROP TRIGGER IF EXISTS acl_rebuild_perm_tree_trigger ON acl.acl_perm;
CREATE TRIGGER acl_rebuild_perm_tree_trigger
    AFTER INSERT OR DELETE ON acl.acl_perm
    FOR EACH STATEMENT
    EXECUTE FUNCTION acl.trigger_acl_rebuild_perm_tree();

CREATE OR REPLACE FUNCTION acl.acl_prevent_perm_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Permissions are suppoesd to be immutable to prevent hierachy corruption. Delete and Insert instead.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acl_prevent_perm_update_trigger
    BEFORE UPDATE ON acl.acl_perm
    FOR EACH STATEMENT
    EXECUTE FUNCTION acl.acl_prevent_perm_update();


-- Function to get all children
-- ORDER BY depth ASC is required to traverse in the correct order when selecting from the returned table
CREATE FUNCTION acl.acl_find_perm_descendants_inclusive(p_perm_id BIGINT)
RETURNS TABLE(acl_perm_id BIGINT, parent_perm_id BIGINT, depth INT) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE children AS (
        SELECT pt.acl_perm_id, pt.parent_perm_id, 0 AS depth
        FROM acl.acl_perm_tree pt
        WHERE pt.acl_perm_id = p_perm_id
        
        UNION ALL
        
        SELECT pt.acl_perm_id, pt.parent_perm_id, c.depth + 1
        FROM acl.acl_perm_tree pt
        INNER JOIN children c ON pt.parent_perm_id = c.acl_perm_id
    )
    SELECT * FROM children;
END;
$$ LANGUAGE plpgsql;

-- Function to get all parents
-- ORDER BY depth ASC is required to traverse in the correct order when selecting from the returned table
CREATE FUNCTION acl.acl_find_perm_ancestors_inclusive(p_perm_id BIGINT)
RETURNS TABLE(acl_perm_id BIGINT, parent_perm_id BIGINT, depth INT) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE parents AS (
        SELECT pt.acl_perm_id, pt.parent_perm_id, 0 AS depth
        FROM acl.acl_perm_tree pt
        WHERE pt.acl_perm_id = p_perm_id
        
        UNION ALL
        
        SELECT pt.acl_perm_id, pt.parent_perm_id, p.depth + 1
        FROM acl.acl_perm_tree pt
        INNER JOIN parents p ON pt.acl_perm_id = p.parent_perm_id
    )
    SELECT * FROM parents;
END;
$$ LANGUAGE plpgsql;