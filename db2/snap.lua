local env=env
local grid=env.db2,env.grid
local cfg=env.set

local snap=env.class(env.snapper)
function snap:ctor()
    self.db=env.db2
    self.command="snap"
    self.help_title='Calculate a period of db/session performance/waits. '
    self.script_dir=env.WORK_DIR.."db2"..env.PATH_DEL.."snap"
end

function snap:get_db_time()
    return self.db:get_value("select /*INTERNAL_DBCLI_CMD*/ to_char(current timestamp,'YYYY-MM-DD HH24:MI:SS') FROM sysibm.sysdummy1")
end

function snap:onload()
    self.validate_accessable=self.db.C.sql.validate_accessable
end

return snap.new()
