/*[[Show instance parameters, including hidden parameters, pls use 'set instance' to show the specific instance. Usage: param [<keyword1>[,<keyword2>...]]]]*/
SELECT x.inst_id,ksppinm NAME, ksppity TYPE, substr(ksppstdvl,1,80) DISPLAY_VALUE, ksppstdf ISDEFAULT,
       decode(bitand(ksppiflg / 256, 1), 1, 'TRUE', 'FALSE') ISSES_Mdf,
       decode(bitand(ksppiflg / 65536, 3), 1, 'IMMEDIATE', 2, 'DEFERRED', 3, 'IMMEDIATE', 'FALSE') ISSYS_MDF,
       decode(bitand(ksppiflg, 4),
               4,
               'FALSE',
               decode(bitand(ksppiflg / 65536, 3), 0, 'FALSE', 'TRUE')) ISINST_MDF,
       decode(bitand(ksppstvf, 7), 1, 'MODIFIED', 4, 'SYSTEM_MOD', 'FALSE') ISMODIFIED,
       decode(bitand(ksppstvf, 2), 2, 'TRUE', 'FALSE') ISDEPRECATED,ksppdesc DESCRIPTION
FROM   (select x.*,min(inst_id) over() m_inst from x$ksppi x) x, x$ksppcv y
WHERE  (x.indx = y.indx)
AND    x.m_inst=x.inst_id
AND   ((:V1 is not null and (ksppinm LIKE LOWER('%'||:V1||'%') or lower(ksppdesc) LIKE LOWER('%'||:V1||'%')) or
       :V2 is not null and (ksppinm LIKE LOWER('%'||:V2||'%') or lower(ksppdesc) LIKE LOWER('%'||:V2||'%')) or
       :V3 is not null and (ksppinm LIKE LOWER('%'||:V3||'%') or lower(ksppdesc) LIKE LOWER('%'||:V3||'%')) or
       :V4 is not null and (ksppinm LIKE LOWER('%'||:V4||'%') or lower(ksppdesc) LIKE LOWER('%'||:V4||'%')) or
       :V5 is not null and (ksppinm LIKE LOWER('%'||:V5||'%') or lower(ksppdesc) LIKE LOWER('%'||:V5||'%'))) 
  OR (:V1 is null and ksppstdf='FALSE'))
ORDER BY 1,NAME;