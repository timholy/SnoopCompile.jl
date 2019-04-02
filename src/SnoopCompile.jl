module SnoopCompile

using Serialization

export @snoopc
if VERSION >= v"1.2.0-DEV.573"
    export @snoopi

    const __inf_timing__ = Tuple{Float64,Core.MethodInstance}[]

    function typeinf_ext_timed(linfo::Core.MethodInstance, params::Core.Compiler.Params)
        tstart = time()
        ret = Core.Compiler.typeinf_ext(linfo, params)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        return ret
    end
    function typeinf_ext_timed(linfo::Core.MethodInstance, world::UInt)
        tstart = time()
        ret = Core.Compiler.typeinf_ext(linfo, world)
        tstop = time()
        push!(__inf_timing__, (tstop-tstart, linfo))
        return ret
    end

    function sort_timed_inf(tmin)
        data = __inf_timing__
        if tmin > 0
            data = filter(tl->tl[1] >= tmin, data)
        end
        return sort(data; by=tl->tl[1])
    end

    """
        inf_timing = @snoopi commands
        inf_timing = @snoopi tmin=0.0 commands

    Execute `commands` while snooping on inference. Returns an array of `(t, linfo)`
    tuples, where `t` is the amount of time spent infering `linfo` (a `MethodInstance`).

    Methods that take less time than `tmin` will not be reported.
    """
    macro snoopi(args...)
        tmin = 0.0
        if length(args) == 1
            cmd = args[1]
        elseif length(args) == 2
            a = args[1]
            if isa(a, Expr) && a.head == :(=) && a.args[1] == :tmin
                tmin = a.args[2]
                cmd = args[2]
            else
                error("unrecognized input ", a)
            end
        else
            error("at most two arguments are supported")
        end
        quote
            empty!($__inf_timing__)
            ccall(:jl_set_typeinf_func, Cvoid, (Any,), $typeinf_ext_timed)
            try
                $(esc(cmd))
            finally
                ccall(:jl_set_typeinf_func, Cvoid, (Any,), Core.Compiler.typeinf_ext)
            end
            $sort_timed_inf($tmin)
        end
    end
end

"""
```
@snoopc "compiledata.csv" begin
    # Commands to execute, in a new process
end
```
causes the julia compiler to log all functions compiled in the course
of executing the commands to the file "compiledata.csv". This file
can be used for the input to `SnoopCompile.read`.
"""
macro snoopc(flags, filename, commands)
    return :(snoopc($(esc(flags)), $(esc(filename)), $(QuoteNode(commands))))
end
macro snoopc(filename, commands)
    return :(snoopc(String[], $(esc(filename)), $(QuoteNode(commands))))
end

function snoopc(flags, filename, commands)
    println("Launching new julia process to run commands...")
    # addprocs will run the unmodified version of julia, so we
    # launch it as a command.
    code_object = """
            using Serialization
            while !eof(stdin)
                Core.eval(Main, deserialize(stdin))
            end
            """
    process = open(`$(Base.julia_cmd()) $flags --eval $code_object`, stdout, write=true)
    serialize(process, quote
        let io = open($filename, "w")
            ccall(:jl_dump_compiles, Nothing, (Ptr{Nothing},), io.handle)
            try
                $commands
            finally
                ccall(:jl_dump_compiles, Nothing, (Ptr{Nothing},), C_NULL)
                close(io)
            end
        end
        exit()
    end)
    wait(process)
    println("done.")
    nothing
end

function split2(str, on)
    i = findfirst(isequal(on), str)
    i === nothing && return str, ""
    return (SubString(str, firstindex(str), prevind(str, first(i))),
            SubString(str, nextind(str, last(i))))
end

"""
`SnoopCompile.read("compiledata.csv")` reads the log file produced by the compiler and returns the functions as a pair of arrays. The first array is the amount of time required to compile each function, the second is the corresponding function + types. The functions are sorted in order of increasing compilation time. (The time does not include the cost of nested compiles.)
"""
function read(filename)
    times = Vector{UInt64}()
    data = Vector{String}()
    toplevel = false # workaround for Julia#22538
    for line in eachline(filename)
        if toplevel
            if endswith(line, '"')
                toplevel = false
            end
            continue
        end
        time, str = split2(line, '\t')
        length(str) < 2 && continue
        (str[1] == '"' && str[end] == '"') || continue
        if startswith(str, """"<toplevel thunk> -> """)
            # consume lines until we find the terminating " character
            toplevel = true
            continue
        end
        tm = tryparse(UInt64, time)
        tm === nothing && continue
        push!(times, tm)
        push!(data, str[2:prevind(str, lastindex(str))])
    end
    # Save the most costly for last
    p = sortperm(times)
    return (permute!(times, p), permute!(data, p))
end

# pattern match on the known output of jl_static_show
extract_topmod(e::QuoteNode) = extract_topmod(e.value)
function extract_topmod(e)
    Meta.isexpr(e, :.) &&
        return extract_topmod(e.args[1])
    Meta.isexpr(e, :call) && length(e.args) == 3 && e.args[1] == :getfield &&
        return extract_topmod(e.args[2])
    Meta.isexpr(e, :call) && length(e.args) == 2 && e.args[1] == :typeof &&
        return extract_topmod(e.args[2])
    #Meta.isexpr(e, :call) && length(e.args) == 2 && e.args[1] == :Symbol &&
    #    return Symbol(e.args[2])
    # parametrized anonymous functions
    Meta.isexpr(e, :call) && e.args[1].args[1] == :getfield &&
        return extract_topmod(e.args[1].args[2].args[2])
    isa(e, Symbol) &&
        return e
    return :unknown
end

function parse_call(line; subst=Vector{Pair{String, String}}(), blacklist=String[])
    for (k, v) in subst
        line = replace(line, k=>v)
    end
    if any(b -> occursin(b, line), blacklist)
        println(line, " contains a blacklisted substring")
        return false, line, :unknown
    end

    curly = ex = Meta.parse(line, raise=false)
    while Meta.isexpr(curly, :where)
        curly = curly.args[1]
    end
    if !Meta.isexpr(curly, :curly)
        @warn("failed parse of line: ", line)
        return false, line, :unknown
    end
    func = curly.args[2]
    topmod = (func isa Expr ? extract_topmod(func) : :Main)

    # make some substitutions to try to form a leaf types tuple
    changed = false
    for i in 3:length(curly.args)
        e = curly.args[i]
        if Meta.isexpr(e, :where) && length(e.args) == 2 && Meta.isexpr(e.args[1], :curly) && length(e.args[1].args) == 3 && e.args[1].args[1] === :Vararg
            # Unwrap a Varargs argument, make it a single instance of the allowed Varargs type.
            e = e.args[1].args[2]
            curly.args[i] = e
            changed = true
        end
        if e === :Function
            # `Function` is not an allowable type for `precompile()`
            e = :(typeof(identity))
        elseif e === :Any
            # `Any` is an abstract type, and can't be precompiled for. Replace it with something that can.
            e = :Int
        elseif e == :(Type{T} where T)
            # Type is an abstract type; replace it with a concrete type.
            e = :(Type{Int})
        else
            continue
        end
        curly.args[i] = e
        changed = true
    end
    # In Julia 0.6, functions with symbolic names like `Base.:(+)` don't output correctly.
    # So if we didn't change the arg list above, use the original string.
    if changed
        line = string(ex)
    end
    return true, line, topmod
end

"""
`pc = parcel(calls; subst=[], blacklist=[])` assigns each compile statement to the module that owns the function. Perform string substitution via `subst=["Module1"=>"Module2"]`, and omit functions in particular modules with `blacklist=["Module3"]`. On output, `pc[:Module2]` contains all the precompiles assigned to `Module2`.

Use `SnoopCompile.write(prefix, pc)` to generate a series of files in directory `prefix`, one file per module.
"""
function parcel(calls; subst=Vector{Pair{String, String}}(), blacklist=String[])
    pc = Dict{Symbol, Vector{String}}()
    for c in calls
        local keep, pcstring, topmod
        keep, pcstring, topmod = parse_call(c, subst=subst, blacklist=blacklist)
        keep || continue
        # Add to the appropriate dictionary
        if !haskey(pc, topmod)
            pc[topmod] = String[]
        end
        push!(pc[topmod], "precompile($pcstring)")
    end
    return pc
end

"""
`pc = format_userimg(calls; subst=[], blacklist=[])` generates precompile directives intended for your base/userimg.jl script. Use `SnoopCompile.write(filename, pc)` to create a file that you can `include` into `userimg.jl`.
"""
function format_userimg(calls; subst=Vector{Pair{String, String}}(), blacklist=String[])
    pc = Vector{String}()
    for c in calls
        keep, pcstring, topmod = parse_call(c, subst=subst, blacklist=blacklist)
        keep || continue
        push!(pc, "precompile($pcstring)")
    end
    return pc
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
    nothing
end

"""
    write(prefix::AbstractString, pc::Dict; always::Bool = false)

Write each modules' precompiles to a separate file.  If `always` is
true, the generated function will always run the precompile statements
when called, otherwise the statements will only be called during
package precompilation.
"""
function write(prefix::AbstractString, pc::Dict; always::Bool = false)
    if !isdir(prefix)
        mkpath(prefix)
    end
    for (k, v) in pc
        open(joinpath(prefix, "precompile_$k.jl"), "w") do io
            println(io, "function _precompile_()")
            !always && println(io, "    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing")
            for ln in v
                println(io, "    ", ln)
            end
            println(io, "end")
        end
    end
end

macro snoop(args...)
    @warn "@snoop is deprecated, use @snoopc instead"
    :(@snoopc $(args...))
end

if VERSION >= v"1.2.0-DEV.573"
    function __init__()
        # typeinf_ext_timed must be compiled before it gets run
        # We do this in __init__ to make sure it gets compiled to native code
        # (the *.ji file stores only the inferred code)
        precompile(typeinf_ext_timed, (Core.MethodInstance, Core.Compiler.Params))
        precompile(typeinf_ext_timed, (Core.MethodInstance, UInt))
        nothing
    end
end

end # module
