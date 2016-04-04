module SnoopCompile

using Compat

export
    snoop_on,
    snoop_off,
    @snoop,
    @snoop1


# If we don't have a JULIAHOME environment variable, set it here.
if !haskey(ENV, "JULIAHOME")
    ENV["JULIAHOME"] = dirname(dirname(JULIA_HOME))
end

function snoop_path()
    snoopdir = Base.find_in_path("SnoopCompile.jl")
    isempty(snoopdir) && error("SnoopCompile is not your path, please fix (e.g., push!(LOAD_PATH, \"/path/to/SnoopCompile\"))")
    splitdir(snoopdir)[1]
end

"""
`snoop_on()` modifies the julia compiler to turn on logging. To
actually use logging, you'll need to start a fresh julia session and
then use `@snoop1`. When finished, restore the compiler to its
original state with `snoop_off()`.
"""
function snoop_on()
    if VERSION < v"0.5.0-dev+210"
        println("Turning on compiler logging")
        cd(snoop_path()) do
            run(`sh snoop.sh ""`)
        end
    end
end

"""
`snoop_off()` restores the julia compiler to its original
state. Alternatively, you can just use `git checkout src/codegen.cpp
&& make` from the julia source folder.
"""
function snoop_off()
    if VERSION < v"0.5.0-dev+210"
        println("Restoring compiler to original state")
        cd(snoop_path()) do
            run(`sh snoop.sh "--reverse"`)
        end
    end
end
"""
```
@snoop "compiledata.csv" begin
    # Commands to execute
end
```
causes the julia compiler to log all functions compiled in the course
of executing the commands to the file "compiledata.csv".  This file
can be used for the input to `SnoopCompile.read`.

After recompiling `codegen.cpp`, this launches a new julia process in
which to run the commands. Once finished, it closes the process and
restores `codegen.cpp` to its original state.  If you're recompiling
manually with `snoop_on()` and `snoop_off()`, use `@snoop1` in a fresh
julia session instead.
"""
macro snoop(filename, commands)
    snoop_on()
    try
        println("Launching new julia process to run commands...")
        # addprocs will run the unmodified version of julia, so we
        # launch it as a command.
        code_object = """
            while !eof(STDIN)
                eval(Main, deserialize(STDIN))
            end
            """
        io, pobj = open(`$(Base.julia_cmd()) --eval $code_object`, "w", STDOUT)
        serialize(io, quote
            using SnoopCompile
        end)
        # Now that the new process knows about SnoopCompile, it can
        # deserialize this next expression
        serialize(io, quote
            @snoop1 $filename $commands
        end)
        close(io)
        wait(pobj)
        println("done.")
    finally
        snoop_off()
    end
    nothing
end

"""
```
@snoop1 "compiledata.csv" begin
    # Commands to execute
end
```
causes the julia compiler to log all functions compiled in the course
of executing the commands to the file "compiledata.csv".  This file
can be used for the input to `SnoopCompile.read`.

You must run this in a julia session that has been started freshly
since turning on snooping with `snoop_on()`.
"""
macro snoop1(filename, commands)
    _snoop1(filename, commands)
end

function _snoop1(filename, commands)
    quote
        io = open($filename, "w")
        ccall(:jl_dump_compiles, Void, (Ptr{Void},), io.handle)
        try
            $(esc(commands))
        finally
            ccall(:jl_dump_compiles, Void, (Ptr{Void},), C_NULL)
            close(io)
        end
    end
end

"""
`SnoopCompile.read("compiledata.csv")` reads the log file produced by the compiler and returns the functions as an 2-column array. The first column is the amount of time required to compile each function, the second is the corresponding function + types. The functions are sorted in order of increasing compilation time. (The time does not include the cost of nested compiles.)
"""
function read(filename)
    data = readdlm(filename, '\t')
    # Save the most costly for last
    p = sortperm(data[:,1])
    data[p,:]
end

function parse_call(c; subst = Dict(), blacklist=UTF8String[])
    fpath = [""]
    args = ""
    hash_handled = match(r"#[0-9]", c) == nothing  # gensyms and anonymous functions on 0.5
    if hash_handled && contains(c, ".#") && VERSION >= v"0.5.0-dev"
        cold = c
        csplit = split_keepdelim(c, ('(',',',')','{','}'))
        fname = split(csplit[1], ".")[end]
        csplit = map(1:length(csplit)) do idx
            s = csplit[idx]
            if contains(s, ".#")
                snew = replace(s, r"#", "")
                sname = split(snew, ".")[end]
                if idx == 3 && sname == fname
                    # Omit the first argument, which is just the
                    # function name all over again
                    return ""
                else
                    return string("typeof(", snew, ')')
                end
            else
                return s
            end
        end
        c = string(csplit...)
        c = replace(c, "(, ", "(")
        c = replace(c, "(,", "(")
    end
    if !hash_handled || contains(c, "#")
        return false, c, fpath, args    # skip gensyms
    end
    for (k,v) in subst
        c = replace(c, k, v)
    end
    if any(b->contains(c, b), blacklist)
        println(c, " is blacklisted")
        return false, c, fpath, args
    end
    argsidx = search(c, '(')
    if argsidx == 0
        error("No function call syntax found, c is ", c)
    end
    fstr, args = c[1:argsidx-1], c[argsidx+1:end-1]
    ## Parse and validate the function
    # Make sure this is a generic function
    fpath = filter(x->!isempty(x), split(fstr, "."))
    if !isempty(search(c, "anonymous")) # anonymous function on 0.4
        return false, c, fpath, args
    end
    # Make sure the module is defined
    local mod
    try
        mod = eval(Main, parse(join(fpath[1:end-1], ".")))
    catch
        return false, c, fpath, args
    end
    if !isdefined(mod, symbol(fpath[end]))
        println("skipping ", fstr)
        return false, c, fpath, args
    end
    fname = convert(UTF8String, fpath[end])
    chr = first(fname)
    if !isalnum(chr) && chr!='_'
        # operators just cause too much trouble to be worth precompiling
        return false, c, fpath, args
    end
    fname = string(mod, ".", fname)
    ## Parse the arguments
    # If the last argument is a Vararg, remove it
    varg = search(args, "Vararg")
    if !isempty(varg)
        args = strip(args[1:first(varg)-1])
        if !isempty(args) && last(args) == ','
            args = args[1:end-1]
        end
    end
    contains(args, "<:") && return false, c, fpath, args   # skip TypeVar types
    if !isempty(args)
        # we insert a comma to ensure tuples for single-argument functions
        args = string("(", args, ",)")
    else
        args = "()"
    end
    # Make sure we can eval the arg types
    try
        eval(Main, parse(args))
    catch
        return false, c, fpath, args
    end
    pcstring = string("    precompile(", fname, ", ", args, ")")
    true, pcstring, fpath, args
end

"""
`pc, discards = parcel(calls; subst=Dict(), blacklist = UTF8String[])` assigns each compile statement to the module that owns the function. Perform string substitution via `subst=Dict("Module1"=>"Module2")`, and omit functions in particular modules with `blacklist=["Module3"]`.  On output, `pc["Module2"]` contains all the precompiles assigned to `Module2`, and `discards` contains functions that had arguments spanning modules and which therefore could not be assigned to a particular module.

Use `SnoopCompile.write(prefix, pc)` to generate a series of files in directory `prefix`, one file per module.
"""
function parcel(calls; subst=Dict(), blacklist=UTF8String[])
    pc = Dict{UTF8String,Vector{UTF8String}}()
    discards = UTF8String[]
    local keep, pcstring, fpath, args
    for c in calls
        try
            keep, pcstring, fpath, args = parse_call(c, blacklist=blacklist)
        catch
            println("error processing ", c)
            rethrow()
        end
        keep || continue
        # Add to the appropriate dictionary
        modname = fpath[1]
        try
            eval(Main.eval(symbol(modname)), parse(args))
        catch
            push!(discards, pcstring)
            continue
        end
        if !haskey(pc, modname)
            pc[modname] = UTF8String[]
        end
        push!(pc[modname], pcstring)
    end
    pc, discards
end

"""
`pc = format_userimg(calls; subst=Dict(), blacklist = UTF8String[])` generates precompile directives intended for your base/userimg.jl script.  Use `SnoopCompile.write(filename, pc)` to create a file that you can `include` into `userimg.jl`.
"""
function format_userimg(calls; subst=Dict(), blacklist=UTF8String[])
    pc = Array(UTF8String,0)
    for c in calls
        keep, pcstring, fpath, args = parse_call(c, blacklist=blacklist)
        keep || continue
        push!(pc, pcstring)
    end
    pc
end

# Write precompiles for userimg.jl
function write(io::IO, pc::Vector)
    for ln in pc
        println(io, ln)
    end
end
function write(filename::AbstractString, pc::Vector)
    path, fn = splitdir(filename)
    if !isdir(path)
        mkpath(path)
    end
    open(filename, "w") do io
        write(io, pc)
    end
end

# Write each modules' precompiles to a separate file
function write(prefix::AbstractString, pc::Dict)
    if !isdir(prefix)
        mkpath(prefix)
    end
    for (k,v) in pc
        open(joinpath(prefix, "precompile_$k.jl"), "w") do io
            println(io, "function _precompile_()")
            println(io, "    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing")
            for ln in v
                println(io, ln)
            end
            println(io, "end")
        end
    end
end

# copied from split
function split_keepdelim{T<:AbstractString,U<:Array}(str::T, splitter, limit::Integer=0, keep_empty::Bool=true, strs::U=[])
    i = start(str)
    n = endof(str)
    r = search(str,splitter,i)
    j, k = first(r), nextind(str,last(r))
    while 0 < j <= n && length(strs) != limit-1
        if i < k
            if keep_empty || i < j
                push!(strs, SubString(str,i,prevind(str,j)))
                push!(strs, SubString(str,j,j))
            end
            i = k
        end
        if k <= j; k = nextind(str,j) end
        r = search(str,splitter,k)
        j, k = first(r), nextind(str,last(r))
    end
    if keep_empty || !done(str,i)
        push!(strs, SubString(str,i))
    end
    return strs
end

end # module
