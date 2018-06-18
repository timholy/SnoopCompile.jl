__precompile__()

module SnoopCompile

export
    @snoop,
    @snoop1

"""
```
@snoop "compiledata.csv" begin
    # Commands to execute, in a new process
end
```
causes the julia compiler to log all functions compiled in the course
of executing the commands to the file "compiledata.csv". This file
can be used for the input to `SnoopCompile.read`.
"""
macro snoop(filename, commands)
    return :(snoop($(esc(filename)), $(QuoteNode(commands))))
end

function snoop(filename, commands)
    println("Launching new julia process to run commands...")
    # addprocs will run the unmodified version of julia, so we
    # launch it as a command.
    code_object = """
        while !eof(STDIN)
            eval(Main, deserialize(STDIN))
        end
        """
    in, io = open(`$(Base.julia_cmd()) --eval $code_object`, "w", STDOUT)
    serialize(in, quote
        import SnoopCompile
    end)
    # Now that the new process knows about SnoopCompile, it can
    # expand the macro in this next expression
    serialize(in, quote
          SnoopCompile.@snoop1 $filename $commands
    end)
    close(in)
    wait(io)
    println("done.")
    nothing
end

function split2(str, on)
    i = search(str, on)
    first(i) == 0 && return str, ""
    return (SubString(str, start(str), prevind(str, first(i))),
            SubString(str, nextind(str, last(i))))
end

"""
```
@snoop1 "compiledata.csv" begin
    # Commands to execute
end
```
causes the julia compiler to log all functions compiled in the course
of executing the commands to the file "compiledata.csv". This file
can be used for the input to `SnoopCompile.read`.
"""
macro snoop1(filename, commands)
    filename = esc(filename)
    commands = esc(commands)
    return quote
        let io = open($filename, "w")
            ccall(:jl_dump_compiles, Void, (Ptr{Void},), io.handle)
            try
                $commands
            finally
                ccall(:jl_dump_compiles, Void, (Ptr{Void},), C_NULL)
                close(io)
            end
        end
    end
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
        if startswith(str, "\"<toplevel thunk> -> ")
            # consume lines until we find the terminating " character
            toplevel = true
            continue
        end
        tm = tryparse(UInt64, time)
        tm == nothing && continue
        push!(times, tm)
        push!(data, str[2:prevind(str, endof(str))])
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
    # parametrized anonymous functions	
    Meta.isexpr(e, :call) && e.args[1].args[1] == :getfield &&
        return extract_topmod(e.args[1].args[2].args[2])
    #Meta.isexpr(e, :call) && length(e.args) == 2 && e.args[1] == :Symbol &&
    #    return Symbol(e.args[2])
    isa(e, Symbol) &&
        return e
    return :unknown
end

function parse_call(line; subst=Vector{Pair{String, String}}(), blacklist=String[])
    for (k, v) in subst
        line = replace(line, k, v)
    end
    if any(b -> contains(line, b), blacklist)
        println(line, " contains a blacklisted substring")
        return false, line, :unknown
    end

    argsidx = search(line, '{') + 1
    if argsidx == 1 || !endswith(line, "}")
        @warn("line doesn't end with }", line)
        return false, line, :unknown
    end    
	line = "Tuple{$(line[argsidx:prevind(line, endof(line))])}"
    curly = parse(line, raise=false)	
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
        line = string(curly)
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

# Write each modules' precompiles to a separate file
function write(prefix::AbstractString, pc::Dict)
    if !isdir(prefix)
        mkpath(prefix)
    end
    for (k, v) in pc
        open(joinpath(prefix, "precompile_$k.jl"), "w") do io
            println(io, "function _precompile_()")
            println(io, "    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing")
            for ln in v
                println(io, "    ", ln)
            end
            println(io, "end")
        end
    end
end

end # module
