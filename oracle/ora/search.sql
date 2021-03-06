/*[[search objects with object_id/keyword. Usage: search [object_id|data_object_id|keyword] 
    --[[
        @check_access_obj: dba_objects={dba_objects}, all_objects={dba_objects}
    --]]
]]*/
SELECT *
FROM   (SELECT OWNER,
               OBJECT_NAME,
               SUBOBJECT_NAME,
               OBJECT_ID,
               DATA_OBJECT_ID DATA_OBJECT,
               OBJECT_TYPE,
               CREATED,
               LAST_DDL_TIME  LAST_DDL,
               STATUS,
               TEMPORARY
        FROM   &check_access_obj
        WHERE  UPPER(OWNER || '.' || OBJECT_NAME || chr(1) || OBJECT_ID || chr(1) ||
                     SUBOBJECT_NAME || chr(1) || DATA_OBJECT_ID || chr(1) ||
                     TO_CHAR(CREATED, 'YYYY-MM-DD HH24:MI:SS') || chr(1) ||
                     TO_CHAR(CREATED, 'YYYY-MM-DD HH24:MI:SS') || chr(1) ||
                     TO_CHAR(LAST_DDL_TIME, 'YYYY-MM-DD HH24:MI:SS') || chr(1) || STATUS) LIKE '%' || NVL(UPPER(:V1), 'x') || '%'
        UNION
        SELECT a.owner,
               a.object_name,
               a.procedure_name subobject_name,
               a.object_id,
               a.subprogram_id,
               b.object_type||'.PROCEDURE',
               b.created,
               b.last_ddl_time,
               b.STATUS,
               b.TEMPORARY
        FROM   all_Procedures a, &check_access_obj b
        WHERE  a.object_id = b.object_id
        AND    upper(a.procedure_name || CHR(1) || a.subprogram_id) LIKE '%' || NVL(UPPER(:V1), 'x') || '%'
        ORDER  BY 1, 2)