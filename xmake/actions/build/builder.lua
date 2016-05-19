--!The Automatic Cross-platform Build Tool
-- 
-- XMake is free software; you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation; either version 2.1 of the License, or
-- (at your option) any later version.
-- 
-- XMake is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Lesser General Public License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public License
-- along with XMake; 
-- If not, see <a href="http://www.gnu.org/licenses/"> http://www.gnu.org/licenses/</a>
-- 
-- Copyright (C) 2015 - 2016, ruki All rights reserved.
--
-- @author      ruki
-- @file        builder.lua
--

-- imports
import("core.base.option")
import("core.project.task")
import("core.project.config")
import("core.project.project")
import("core.project.cache")
import("core.tool.tool")
import("core.tool.linker")
import("core.tool.compiler")
import("core.platform.environment")

-- make the object for the *.[o|obj] source file
function _make_object_for_object(target, srcfile, objfile)

    -- TODO
    raise("not implemented")
end

-- make the object for the *.[a|lib] source file
function _make_object_for_static(target, srcfile, objfile)

    raise("not implemented")
    -- TODO
end

-- make object
function _make_object(target, sourcefile, objectfile)

    -- get the source file type
    local filetype = path.extension(sourcefile):lower()

    -- make the object for the *.o/obj source makefile
    if filetype == ".o" or filetype == ".obj" then 
        return _make_object_for_object(target, sourcefile, objectfile)
    -- make the object for the *.[a|lib] source file
    elseif filetype == ".a" or filetype == ".lib" then 
        return _make_object_for_static(target, sourcefile, objectfile)
    end

    -- make command
    local ccache    = tool.shellname("ccache") 
    local command   = compiler.command(target, sourcefile, objectfile)
    if ccache then
        command = ccache:append(command, " ")
    end

    -- trace
    print("%scompiling.$(mode) %s", ifelse(ccache, "ccache ", ""), sourcefile)

    -- trace verbose info
    if option.get("verbose") then
        print(command)
    end

    -- create directory if not exists
    os.mkdir(path.directory(objectfile))

    -- run cmd with coroutine
    os.corun(command)
end

-- make objects for the given target
function _make_objects(target)

    -- the object and source files
    local objectfiles = target:objectfiles()
    local sourcefiles = target:sourcefiles()

    -- get the max job count
    local jobs = tonumber(option.get("jobs") or "4")

    -- make objects
    local index = 1
    local total = #objectfiles
    local tasks = {}
    repeat

        -- consume tasks
        local finished = {}
        for i, task in ipairs(tasks) do

            -- get job
            local job = task[1]

            -- get job index
            local job_index = task[2]

            -- get status
            local status = coroutine.status(job)

            -- finished?
            if status == "dead" then
                table.insert(finished, i)
            else
                -- resume it
                local ok, errors = coroutine.resume(job, job_index)
                if not ok then
                    raise(errors)
                end
            end
        end

        -- remove finished tasks
        for _, i in ipairs(finished) do
            table.remove(tasks, i)
        end

        -- produce tasks
        while #tasks < jobs and index <= total do
            table.insert(tasks, {coroutine.create(function (index)

                        -- make object
                        _make_object(target, sourcefiles[index], objectfiles[index])

                    end), index})
            index = index + 1
        end

    until #tasks == 0

end

-- make the given target
function _make_target(target)

    -- trace
    print("building.$(mode) %s", target:name())

    -- make objects
    _make_objects(target)

    -- make the command for linking target
    local targetfile    = target:targetfile()
    local command       = linker.command(target)

    -- trace
    print("linking.$(mode) %s", path.filename(targetfile))

    -- trace verbose info
    if option.get("verbose") then
        print(command)
    end

    -- create directory if not exists
    os.mkdir(path.directory(targetfile))

    -- run command
    os.run(command)

    -- make headers
    local srcheaders, dstheaders = target:headerfiles()
    if srcheaders and dstheaders then
        local i = 1
        for _, srcheader in ipairs(srcheaders) do
            local dstheader = dstheaders[i]
            if dstheader then
                os.cp(srcheader, dstheader)
            end
            i = i + 1
        end
    end
end

-- make the given target and deps
function _make_target_and_deps(target)

    -- this target have been finished?
    if _g.finished[target:name()] then
        return 
    end

    -- make for all dependent targets
    for _, depname in ipairs(target:get("deps")) do
        _make_target_and_deps(project.target(depname))
    end

    -- make target
    _make_target(target)

    -- finished
    _g.finished[target:name()] = true
end

-- make
function make(targetname)

    -- enter toolchains environment
    environment.enter("toolchains")

    -- init finished states
    _g.finished = {}

    -- for all?
    if targetname == "all" then

        -- make all targets
        for _, target in pairs(project.targets()) do
            _make_target_and_deps(target)
        end
    else

        -- make target
        _make_target_and_deps(project.target(targetname))
    end

    -- leave toolchains environment
    environment.leave("toolchains")
end
