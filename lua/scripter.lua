local env=env
local grid,cfg=env.grid,env.set
local ARGS_COUNT=20

local scripter=env.class()

function scripter:ctor()
    self.script_dir,self.extend_dirs=nil,{}
    self.comment="/%*%s*%[%[(.*)%]%]%s*%*/"
    self.command='sql'
    self.usage="[<script_name>|-r|-p|-h|-s|-g] [parameters]"
    self.ext_name='sql'
    self.help_title=""
    self.help_ind=0
end

function scripter:get_command()
    return type(self.command)=="table" and self.command[1] or self.command
end

function scripter:trigger(func,...)
    if type(self[func])=="function" then
        return self[func](self,...)
    end
end

function scripter:format_version(version)
    return version:gsub("(%d+)",function(s) return s:len()<3 and string.rep('0',3-s:len())..s or s end)
end

function scripter:rehash(script_dir,ext_name)
    local keylist=env.list_dir(script_dir,ext_name or self.ext_name or "sql",self.comment)
    local cmdlist,pathlist={},{}
    local counter=0
    for k,v in ipairs(keylist) do
        if script_dir:match("ssh") then print(table.dump(v)) end
        local desc=v[3] and v[3]:gsub("^%s*[\n\r]+","") or ""
        desc=desc:gsub("%-%-%[%[(.*)%]%]%-%-",""):gsub("%-%-%[%[(.*)%-%-%]%]","")
        desc=desc:gsub("([\n\r]+%s*)%-%-","%1  ")
        desc=desc:gsub("([\n\r]+%s*)REM","%1   ")
        desc=desc:gsub("([\n\r]+%s*)rem","%1   ")
        local cmd=v[1]:upper()
        if cmdlist[cmd] then
            pathlist[cmdlist[cmd].path:lower()]=nil
        end
        cmdlist[cmd]={path=v[2],desc=desc,short_desc=desc:match("([^\n\r]+)") or ""}
        pathlist[v[2]:lower()]=cmd
        counter=counter+1
    end

    local additions={
        {'-R','Rebuild the help info and available commands'},
        {'-P','Verify the paramters/templates of the target script, instead of running it. Usage:  -p <cmd> [<args>]'},
        {'-H','Show the help detail of the target command. Usage:  -h <command>'},
        {'-G','Print the content of the specific command. Usage: -g <command>'},
        {'-S','Search available commands with inputed keyword. Usage:  -s <keyword>'},
        {'@','Run scripts that not belongs to the "'..self.short_dir..'" directory.'},
    }

    for k,v in ipairs(additions) do
        cmdlist[v[1]]={desc=v[2],short_desc=v[2]}
    end

    cmdlist['./PATH'],cmdlist['./COUNT']=pathlist,counter

    return cmdlist
end

--[[
Available parameters:
   Input bindings:  from :V1 to :V9
   Replacement:     from &V1 to &V9, used to replace the wildchars inside the SQL stmts
   Out   bindings:  :<alphanumeric>, the data type of output parameters should be defined in th comment scope
--]]--
function scripter:parse_args(sql,args,print_args)

    local outputlist={}
    local outputcount=0

    --parse template
    local patterns,options={"(%b{})","([^\n\r]-)%s*[\n\r]"},{}

    local desc
    sql=sql:gsub(self.comment,function(item)
        desc=item:match("%-%-%[%[(.*)%]%]%-%-")
        if not desc then desc=item:match("%-%-%[%[(.*)%-%-%]%]") end
        return ""
    end,1)

    args=args or {}
    local orgs,templates={},{}

    local sub_pattern=('w_.$#/'):gsub('(.)',function(s) return '%'..s end)
    sub_pattern='(['..sub_pattern..']+)%s*=%s*(%b{})'

    local function setvalue(param,value,mapping)
        if not orgs[param] then orgs[param]={args[param] or ""} end
        args[param],orgs[param][2]=value,mapping and (param..'['..mapping..']') or ""
    end

    if desc then
        --Parse the  &<V1-V30> and :<V1-V30> grammar, refer to ashtop.sql
        for _,p in ipairs(patterns) do
            for prefix,k,v in desc:gmatch('([&:@])([%w_]+)%s*:%s*'..p) do
                k=k:upper()
                if not templates[k] then--same variable should not define twice
                    templates[k]={}
                    local keys,default={}
                    for option,text in v:gmatch(sub_pattern) do
                        option,text=option:upper(),text:sub(2,-2)
                        default=default or option
                        if prefix~="@" then
                            if not options[option] then options[option]={} end
                            options[option][k]=text
                        else
                            keys[#keys+1]=option
                        end
                        templates[k][option]=text
                    end

                    if prefix=="@" then
                        env.checkerr(self.db:is_connect(),'Database is not connected!')
                        default=self:trigger('validate_accessable',k,keys,templates[k])
                    end

                    templates[k]['@default']=default

                    if not k:match("^(V%d+)$") then
                        setvalue(k,templates[k][templates[k]['@default']],default)
                        templates[k]['@choose']=default
                    end
                end
            end
        end
    end

    --Start to assign template value to args
    for i=1,ARGS_COUNT do
        args[i],args[tostring(i)],args["V"..i]=nil,nil,args["V"..i] or args[i] or args[tostring(i)] or ""
    end

    local arg1,ary={},{}
    for i=1,ARGS_COUNT do
        local k,v="V"..i,tostring(args["V"..i])
        ary[i]=v
        if v:sub(1,1)=="-"  then
            local idx,rest=v:sub(2):match("^([%w_]+)(.*)$")
            if idx then
                idx,rest=idx:upper(),rest:gsub('^"(.*)"$','%1')
                for param,text in pairs(options[idx] or {}) do
                    ary[i]=nil
                    local ary_idx=tonumber(param:match("^V(%d+)$"))
                    if args[param] and ary_idx then
                        ary[ary_idx]=nil
                        arg1[param]=text..rest
                    else
                        setvalue(param,text..rest,idx)
                    end

                    if templates[param] then
                        templates[param]['@choose']=idx
                    end
                end
            end
        end
    end

    for i=ARGS_COUNT,1,-1 do
        if not ary[i] then table.remove(ary,i) end
    end

    for i=1,ARGS_COUNT do
        local param="V"..i
        if arg1[param] then
            table.insert(ary,i,arg1[param])
        end
        if ary[i]=="." then ary[i]="" end
        setvalue(param,ary[i] or "")
        local option=args[param]:upper()
        local template=templates[param]
        if args[param]=="" and template and not arg1[param] then
            setvalue(param,template[template['@default']] or "",template['@default'])
            template['@choose']=template['@default']
        else
            local idx,rest=option:match("^([%w_]+)(.*)$")
            if idx then
                idx,rest=idx:upper(),rest:gsub('^"(.*)"$','%1')
                if options[idx] and options[idx][param] then
                    setvalue(param,options[idx][param]..rest,idx)
                    template['@choose']=idx
                end
            end
        end
    end

    if print_args then
        local rows={{"Variable","Option","Default?","Choosen?","Value"}}
        local rows1={{"Variable","Origin","Mapping","Final"}}
        local keys={}
        for k,v in pairs(args) do
            keys[#keys+1]=k
        end

        table.sort(keys,function(a,b)
            local a1,b1=tostring(a):match("^V(%d+)$"),tostring(b):match("^V(%d+)$")
            if a1 and b1 then return tonumber(a1)<tonumber(b1) end
            if a1 then return true end
            if b1 then return false end
            if type(a)==type(b) then return a<b end
            return tostring(a)<tostring(b)
        end)

        local function strip(text)
            len=146
            text= (text:gsub("%s+"," ")):sub(1,len)
            if text:len()==len then text=text..' ...' end
            return text
        end

        for _,k in ipairs(keys) do
            local ind=0
            local new,template,org=args[k],templates[k],orgs[k] or {}
            if type(template)=="table" then
                local default,select=template['@default'],template['@choose']
                for option,text in pairs(template) do
                    if option~="@default" and option~="@choose" then
                        ind=ind+1
                        rows[#rows+1]={ind==1 and k or "",
                                       option,
                                       default==option and "Y" or "N",
                                       select==option and "Y" or "N",
                                       strip(text)}
                    end
                end
                if #rows>1 then rows[#rows+1]={""} end
            end
            rows1[#rows1+1]={k,strip(org[1] or ""),(org[2] or ''),strip(new)}
        end

        for k,v in pairs(env.var.inputs) do
            if type(k)=="string" and k:upper()==k and type(v)=="string" then
                rows1[#rows1+1]={k,v,"cmd 'def'",v}
            end
        end

        print("Templates:\n================")
        --grid.sort(rows,1,true)
        grid.print(rows)

        print("\nInputs:\n================")
        grid.print(rows1)
    end
    return args
end

function scripter:run_sql(sql,args,print_args)
    if not self.db or not self.db.is_connect then
        env.raise("Database connection is not defined!")
    end

    env.checkerr(self.db:is_connect(),"Database is not connected!")

    if print_args or not args then return end
    --remove comment
    sql=sql:gsub(self.comment,"",1)
    sql=('\n'..sql):gsub("\n[\t ]*%-%-[^\n]*","")
    sql=('\n'..sql):gsub("\n%s*/%*.-%*/",""):gsub("/%s*$","")
    local sq="",cmd,params,pre_cmd,pre_params
    local cmds=env._CMDS

    local ary=env.var.backup_context()
    env.var.import_context(args)
    local eval=env.eval_line
    for line in sql:gsplit("[\n\r]+") do
        eval(line)
    end

    if env.pending_command() then
        env.force_end_input()
    end
    env.var.import_context(ary)
end

function scripter:get_script(cmd,args,print_args)
    if not self.cmdlist or cmd=="-r" or cmd=="-R" then
        self.cmdlist,self.extend_dirs=self:rehash(self.script_dir,self.ext_name),{}
        local keys={}
        for k,_ in pairs(self.cmdlist) do
            keys[#keys+1]=k
        end
    end

    if not cmd then
        return env.helper.helper(self:get_command())
    end

    cmd=cmd:upper()

    if cmd:sub(1,1)=='-' and args[1]=='@' and args[2] then
        args[2]='@'..args[2]
        table.remove(args,1)
    elseif cmd=='@' and args[1] then
        cmd=cmd..args[1]
        table.remove(args,1)
    end
    local is_get=false
    if cmd=="-R" then
        return
    elseif cmd=="-H" then
        return  env.helper.helper(self:get_command(),args[1])
    elseif cmd=="-G" then
        cmd,is_get=args[1] and args[1]:upper() or "/",true
    elseif cmd=="-P" then
        cmd,print_args=args[1] and args[1]:upper() or "/",true
        table.remove(args,1)
    elseif cmd=="-S" then
        return env.helper.helper(self:get_command(),"-S",table.unpack(args))
    end

    local file,f,target_dir
    if cmd:sub(1,1)=="@" then
        target_dir,file=self:check_ext_file(cmd)
        env.checkerr(target_dir['./COUNT']>0,"Cannot find script "..cmd:sub(2))
        if not file then return env.helper.helper(self:get_command(),cmd) end
        cmd,file=file,target_dir[file].path

    elseif self.cmdlist[cmd] then
        file=self.cmdlist[cmd].path
    end
    env.checkerr(file,'Cannot find this script under "'..self.short_dir..'"')

    local f=io.open(file)
    env.checkerr(f,"Cannot find this script!")
    local sql=f:read('*a')
    f:close()
    if is_get then return print(sql) end
    args=self:parse_args(sql,args,print_args)
    return sql,args,print_args,file,cmd
end

function scripter:run_script(cmd,...)
    local args,print_args,sql={...},false
    sql,args,print_args=self:get_script(cmd,args,print_args)
    if not args then return end
    --self._backup_context=env.var.backup_context()
    self:run_sql(sql,args,print_args)
end

function scripter:after_script()
    if self._backup_context then
        env.var.import_context(self._backup_context)
        self._backup_context=nil
    end
end

function scripter:check_ext_file(cmd)
    local target_dir
    cmd=cmd:lower():gsub('^@["%s]*(.-)["%s]*$','%1')
    target_dir=self.extend_dirs[cmd]

    if not target_dir then
        for k,v in pairs(self.extend_dirs) do
            if cmd:find(k,1,true) then
                target_dir=self.extend_dirs[k]
                break
            end
        end

        if not target_dir then
            if not cmd:match('[\\/]([^\\/]+)[\\/]') then env.raise('The target location cannot be under the drive root!') end
            self.extend_dirs[cmd]=self:rehash(cmd,self.ext_name)
            target_dir=self.extend_dirs[cmd]
        end
    end

    if env.file_type(cmd)=='folder' then
        --Remove the settings that only contains one file
        for k,v in pairs(self.extend_dirs) do
            if k:find(cmd,1,true) and v['./COUNT']==1 then
                self.extend_dirs[k]=nil
            end
        end
        return target_dir,nil
    end
    cmd=cmd:match('([^\\/]+)$'):match('[^%.%s]+'):upper()
    return target_dir,cmd
end

function scripter:helper(_,cmd,search_key)
    local help,cmdlist=""
    help=('%sUsage: %s %s \nAvailable commands:\n=================\n'):format(self.help_title,self:get_command(),self.usage)
    self.help_ind=self.help_ind+1
    if self.help_ind==2 and not self.cmdlist then
        self:run_script('-r')
    end
    cmdlist=self.cmdlist
    if cmd and cmd:sub(1,1)=='@' then
        help=""
        cmdlist,cmd=self:check_ext_file(cmd)
    end
    --[[
    format of cmdlist:  {cmd1={short_desc=<brief help>,desc=<help detail>},
                         cmd2={short_desc=<brief help>,desc=<help detail>},
                         ...}
    ]]
    if not cmd or cmd=="-S" then
        if not cmdlist then return help end
        local rows={{},{}}
        local undocs=nil
        local undoc_index=0
        for k,v in pairs(cmdlist) do
            if (not search_key or k:find(search_key:upper(),1,true)) and k:sub(1,2)~='./' and k:sub(1,1)~='_' then
                if search_key or not (v.path or ""):find('[\\/]test[\\/]') then
                    local desc=v.short_desc:gsub("^[ \t]+","")
                    if desc and desc~="" then
                        table.insert(rows[1],k)
                        table.insert(rows[2],desc)
                    else
                        local flag=1
                        if v.path and v.path:lower():find(env.WORK_DIR:lower(),1,true) then
                            local _,degree=v.path:sub(env.WORK_DIR:len()+1):gsub('[\\/]+','')
                            if degree>3 then flag=0 end
                        end

                        if flag==1  then
                            undoc_index=undoc_index+1
                            undocs=(undocs or '')..k..', '
                            if math.fmod(undoc_index,10)==0 then undocs=undocs..'\n' end
                        end
                    end
                end
            end
        end
        if(undocs) then
            undocs=undocs:gsub("[\n%s,]+$",'')
            table.insert(rows[1],'_Undocumented_')
            table.insert(rows[2],undocs)
        end
        env.set.set("PIVOT",-1)
        env.set.set("HEADDEL",":")
        help=help..grid.tostring(rows)
        env.set.restore("HEADDEL")
        return help
    end
    cmd = cmd:upper()
    return cmdlist[cmd] and cmdlist[cmd].desc or "No such command["..cmd.."] !"
end

function scripter:__onload()
    env.checkerr(self.script_dir,"Cannot find the script dir for the '"..self:get_command().."' command!")
    self.db=self.db or env.db_core.__instance
    self.short_dir=self.script_dir:match('([^\\/]+)$')
    env.set_command(self,self.command, self.helper,{self.run_script,self.after_script},false,ARGS_COUNT+1)
end

return scripter