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

function parse_call(line; subst=Vector{Pair{String, String}}(), exclusions=String[])
    match(anonrex, line) === nothing || return false, line, :unknown, ""
    for (k, v) in subst
        line = replace(line, k=>v)
    end
    if any(b -> occursin(b, line), exclusions)
        println(line, " contains an excluded substring")
        return false, line, :unknown, ""
    end

    curly = ex = Meta.parse(line, raise=false)
    while Meta.isexpr(curly, :where)
        curly = curly.args[1]
    end
    if !Meta.isexpr(curly, :curly)
        @warn("failed parse of line: ", line)
        return false, line, :unknown, ""
    end
    func = curly.args[2]
    topmod = (func isa Expr ? extract_topmod(func) : :Main)

    check = Meta.isexpr(func, :call) && length(func.args) == 3 && func.args[1] == :getfield
    name = (check ? func.args[3].args[2] : "")

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
    return true, line, topmod, name
end

"""
`pc = parcel(calls; subst=[], exclusions=[])` assigns each compile statement to the module that owns the function. Perform string substitution via `subst=["Module1"=>"Module2"]`, and omit functions in particular modules with `exclusions=["Module3"]`. On output, `pc[:Module2]` contains all the precompiles assigned to `Module2`.

Use `SnoopCompile.write(prefix, pc)` to generate a series of files in directory `prefix`, one file per module.
"""
function parcel(calls::AbstractVector{String};
    subst=Vector{Pair{String, String}}(),
    exclusions=String[],
    remove_exclusions::Bool = true,
    check_eval::Bool = false,
    blacklist=nothing,                  # deprecated keyword
    remove_blacklist=nothing)           # deprecated keyword

    if blacklist !== nothing
        Base.depwarn("`blacklist` is deprecated, please use `exclusions` to pass a list of excluded names", :parcel)
        append!(exclusions, blacklist)
    end
    if remove_blacklist !== nothing
        Base.depwarn("`remove_blacklist` is deprecated, please use `remove_exclusions` to pass a list of excluded names", :parcel)
        remove_exclusions = remove_blacklist
    end
    pc = Dict{Symbol, Vector{String}}()

    sym_module = Dict{Symbol, Module}() # 1-1 association between modules and module name

    for c in calls
        local keep, pcstring, topmod
        keep, pcstring, topmod, name = parse_call(c, subst=subst, exclusions=exclusions)
        keep || continue
        # Add to the appropriate dictionary
        if !haskey(pc, topmod)
            pc[topmod] = String[]
        end
        prefix = (isempty(name) ? "" : "isdefined($topmod, Symbol(\"$name\")) && ")
        push!(pc[topmod], prefix * "precompile($pcstring)")

        # code from parcel_snoopi
        # TODO moduleof a symobl!
        # eval(topmod) # throws error for Test
        # sym_module[topmod] = moduleof(topmod)
    end

    # TODO
    # for mod in keys(pc)
    #     # check_eval remover
    #     if check_eval
    #         pc[mod] = remove_if_not_eval!(pc[mod], sym_module[mod])
    #     end
    # end
    return pc
end

"""
`pc = format_userimg(calls; subst=[], exclusions=[])` generates precompile directives intended for your base/userimg.jl script. Use `SnoopCompile.write(filename, pc)` to create a file that you can `include` into `userimg.jl`.
"""
function format_userimg(calls; subst=Vector{Pair{String, String}}(), exclusions=String[])
    pc = Vector{String}()
    for c in calls
        keep, pcstring, topmod, name = parse_call(c, subst=subst, exclusions=exclusions)
        keep || continue
        prefix = (isempty(name) ? "" : "isdefined($topmod, Symbol(\"$name\")) && ")
        push!(pc, prefix * "precompile($pcstring)")
    end
    return pc
end

# TODO Make this work with snoopc:

"""
    remove_if_not_eval!(pcstatements, modul::Module)

Removes everything statement in `pcstatements` can't be `eval`ed in `modul`.

# Example

```jldoctest; setup=:(using SnoopCompile), filter=r":\\d\\d\\d"
julia> pcstatements = ["precompile(sum, (Vector{Int},))", "precompile(sum, (CustomVector{Int},))"];

julia> SnoopCompile.remove_if_not_eval!(pcstatements, Base)
┌ Warning: Faulty precompile statement: precompile(sum, (CustomVector{Int},))
│   exception = UndefVarError: CustomVector not defined
└ @ Base precompile_Base.jl:375
1-element Array{String,1}:
 "precompile(sum, (Vector{Int},))"
```
"""
function remove_if_not_eval!(pcstatements, modul::Module)
    todelete = Set{eltype(pcstatements)}()
    for line in pcstatements
        try
            if modul === Core
                #https://github.com/timholy/SnoopCompile.jl/issues/76
                Core.eval(Main, Meta.parse(line))
            else
                Core.eval(modul, Meta.parse(line))
            end
        catch e
            @warn("Faulty precompile statement: $line", exception = e, _module = modul, _file = "precompile_$modul.jl")
            push!(todelete, line)
        end
    end
    return setdiff!(pcstatements, todelete)
end
