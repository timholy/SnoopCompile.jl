#using LightGraph
#using AbstractTrees
using Serialization

function topmodule(mods)
    function ischild(c, mod)
        ok = false
        pc = parentmodule(c)
        while pc !== c
            pc === Main && return false  # mostly important for passing the tests
            if isdefined(mod, nameof(pc))
                ok = true
                break
            end
            c = pc
        end
        return ok
    end

    mods = collect(mods)
    mod = first(mods)
    for m in Iterators.drop(mods, 1)
        # Easy cases
        if isdefined(mod, nameof(m))
        elseif isdefined(m, nameof(mod))
            mod = m
        else
            # Check parents of each
            if ischild(m, mod)
            elseif ischild(mod, m)
                mod = m
            else
                return nothing
            end
        end
    end
    return mod
end

function addmodules!(mods, parameters)
    for p in parameters
        if isa(p, DataType)
            push!(mods, Base.moduleroot(p.name.module))
            addmodules!(mods, p.parameters)
        end
    end
    return mods
end

function methods_with_generators(m::Module)
    meths = Method[]
    for name in names(m; all=true)
        isdefined(m, name) || continue
        f = getfield(m, name)
        if isa(f, Function)
            for method in methods(f)
                if isdefined(method, :generator)
                    push!(meths, method)
                end
            end
        end
    end
    return meths
end

# Code to look up keyword-function "body methods"
const lookup_kwbody_str = """
const __bodyfunction__ = Dict{Method,Any}()

# Find keyword "body functions" (the function that contains the body
# as written by the developer, called after all missing keyword-arguments
# have been assigned values), in a manner that doesn't depend on
# gensymmed names.
# `mnokw` is the method that gets called when you invoke it without
# supplying any keywords.
function __lookup_kwbody__(mnokw::Method)
    function getsym(arg)
        isa(arg, Symbol) && return arg
        @assert isa(arg, GlobalRef)
        return arg.name
    end

    f = get(__bodyfunction__, mnokw, nothing)
    if f === nothing
        fmod = mnokw.module
        # The lowered code for `mnokw` should look like
        #   %1 = mkw(kwvalues..., #self#, args...)
        #        return %1
        # where `mkw` is the name of the "active" keyword body-function.
        ast = Base.uncompressed_ast(mnokw)
        if isa(ast, Core.CodeInfo) && length(ast.code) >= 2
            callexpr = ast.code[end-1]
            if isa(callexpr, Expr) && callexpr.head == :call
                fsym = callexpr.args[1]
                if isa(fsym, Symbol)
                    f = getfield(fmod, fsym)
                elseif isa(fsym, GlobalRef)
                    if fsym.mod === Core && fsym.name === :_apply
                        f = getfield(mnokw.module, getsym(callexpr.args[2]))
                    elseif fsym.mod === Core && fsym.name === :_apply_iterate
                        f = getfield(mnokw.module, getsym(callexpr.args[3]))
                    else
                        f = getfield(fsym.mod, fsym.name)
                    end
                else
                    f = missing
                end
            else
                f = missing
            end
        else
            f = missing
        end
        __bodyfunction__[mnokw] = f
    end
    return f
end
"""

const lookup_kwbody_ex = Expr(:toplevel)
start = 1
while true
    global start
    ex, start = Meta.parse(lookup_kwbody_str, start)
    if ex !== nothing
        push!(lookup_kwbody_ex.args, ex)
    else
        break
    end
end

"""
    can_eval(mod::Module, str::AbstractString, check_eval::Bool=true)

Checks if the precompilation statement can be evaled.

In some cases, you may want to bypass this function by passing `check_eval=true` to increase the snooping performance.
"""
function can_eval(mod::Module, str::AbstractString, check_eval::Bool=true)
    if check_eval
        try
            ex = Meta.parse(str)
            if mod === Core
                #https://github.com/timholy/SnoopCompile.jl/issues/76
                Core.eval(Main, ex)
            else
                Core.eval(mod, ex)
            end
        catch e
            return false, e
        end
    end
    return true, nothing
end

tupletypestring(params) = "Tuple{" * join(params, ',') * '}'
tupletypestring(fstr::AbstractString, params::AbstractVector{<:AbstractString}) =
    tupletypestring([fstr; params])

tuplestring(params) = isempty(params) ? "()" : '(' * join(params, ',') * ",)"

wrap_precompile(ttstr::AbstractString) = "Base.precompile(" * ttstr * ')' # use `Base.` to avoid conflict with Core and Pkg

"""
     add_if_evals!(pclist, mod::Module, fstr, params, tt; prefix = "", check_eval::Bool=true)

Adds the precompilation statements only if they can be evaled. It uses [`can_eval`](@ref) internally.

In some cases, you may want to bypass this function by passing `check_eval=true` to increase the snooping performance.
"""
function add_if_evals!(pclist, mod::Module, fstr, params, tt; prefix = "", check_eval::Bool=true)
    ttstr = tupletypestring(fstr, params)
    can, exc = can_eval(mod, ttstr, check_eval)
    if can
        push!(pclist, prefix*wrap_precompile(ttstr))
    else
        @debug "Module $mod: skipping $tt due to eval failure" exception=exc _module=mod _file="precompile_$mod.jl"
    end
    return pclist
end

function reprcontext(mod::Module, @nospecialize(T::Type))
    # First try without the full module context
    rplain = repr(T)
    try
        ex = Meta.parse(rplain)
        Core.eval(mod, ex)
        return rplain
    catch
        # Add full module context
        return repr(T; context=:module=>nothing)
    end
end

function handle_kwbody(topmod::Module, m::Method, paramrepr, tt, fstr="fbody"; check_eval = true)
    nameparent = Symbol(match(r"^#([^#]*)#", String(m.name)).captures[1])
    if !isdefined(m.module, nameparent)   # TODO: replace debugging with error-handling
        @show m m.name
    end
    fparent = getfield(m.module, nameparent)
    pttstr = tuplestring(paramrepr[m.nkw+2:end])
    whichstr = "which($(repr(fparent)), $pttstr)"
    can1, exc1 = can_eval(topmod, whichstr, check_eval)
    if can1
        ttstr = tuplestring(paramrepr)
        pcstr = """
        let fbody = try __lookup_kwbody__($whichstr) catch missing end
                if !ismissing(fbody)
                    precompile($fstr, $ttstr)
                end
            end"""  # extra indentation because `write` will indent 1st line
        can2, exc2 = can_eval(topmod, pcstr, check_eval)
        if can2
            return pcstr
        else
            @debug "Module $topmod: skipping $tt due to kwbody lookup failure" exception=exc2 _module=topmod _file="precompile_$topmod.jl"
        end
    else
        @debug "Module $topmod: skipping $tt due to kwbody caller lookup failure" exception=exc1 _module=topmod _file="precompile_$topmod.jl"
    end
    return nothing
end

function parcel(tinf::AbstractVector{Tuple{Float64, Core.MethodInstance}};
    subst = Vector{Pair{String, String}}(),
    exclusions = String[],
    remove_exclusions::Bool = true,
    check_eval::Bool = true,
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

    pc = Dict{Symbol, Set{String}}()         # output
    modgens = Dict{Module, Vector{Method}}() # methods with generators in a module
    mods = OrderedSet{Module}()                     # module of each parameter for a given method
    sym_module = Dict{Symbol, Module}() # 1-1 association between modules and module name
    for (t, mi) in reverse(tinf)
        isdefined(mi, :specTypes) || continue
        tt = mi.specTypes
        m = mi.def
        isa(m, Method) || continue
        # Determine which module to assign this method to. All the types in the arguments
        # need to be defined; we collect all the corresponding modules and assign it to the
        # "topmost".
        empty!(mods)
        push!(mods, Base.moduleroot(m.module))
        addmodules!(mods, tt.parameters)
        topmod = topmodule(mods)
        if topmod === nothing
            @debug "Skipping $tt due to lack of a suitable top module"
            continue
        end
        # If we haven't yet started the list for this module, initialize
        topmodname = nameof(topmod)
        sym_module[topmodname] = topmod
        if !haskey(pc, topmodname)
            pc[topmodname] = Set{String}()
            # For testing our precompile directives, we might need to have lookup available
            if VERSION >= v"1.4.0-DEV.215" && topmod !== Core && !isdefined(topmod, :__bodyfunction__)
                Core.eval(topmod, lookup_kwbody_ex)
            end
        end
        # Create the string representation of the signature
        # Use special care with keyword functions, anonymous functions
        p = tt.parameters[1]   # the portion of the signature related to the function itself
        paramrepr = map(T->reprcontext(topmod, T), Iterators.drop(tt.parameters, 1))  # all the rest of the args

        if any(str->occursin('#', str), paramrepr)
            @debug "Skipping $tt due to argument types having anonymous bindings"
            continue
        end
        mname, mmod = String(p.name.name), m.module   # m.name strips the kw identifier
        mkw = match(kwrex, mname)
        mkwbody = match(kwbodyrex, mname)
        isgen = match(genrex, mname) !== nothing
        isanon = match(anonrex, mname) !== nothing || match(innerrex, mname) !== nothing
        isgen && (mkwbody = nothing)
        if VERSION < v"1.4.0-DEV.215"  # before this version, we can't robustly look up kwbody callers (missing `nkw`)
            isanon |= mkwbody !== nothing  # treat kwbody methods the same way we treat anonymous functions
            mkwbody = nothing
        end
        if mkw !== nothing
            # Keyword function
            fname = mkw.captures[1] === nothing ? mkw.captures[2] : mkw.captures[1]
            fkw = "Core.kwftype(typeof($mmod.$fname))"
            add_if_evals!(pc[topmodname], topmod, fkw, paramrepr, tt; check_eval=check_eval)
        elseif mkwbody !== nothing
            ret = handle_kwbody(topmod, m, paramrepr, tt; check_eval = check_eval)
            if ret !== nothing
                push!(pc[topmodname], ret)
            end
        elseif isgen
            # Generator for a @generated function
            if !haskey(modgens, m.module)
                callers = modgens[m.module] = methods_with_generators(m.module)
            else
                callers = modgens[m.module]
            end
            for caller in callers
                if nameof(caller.generator.gen) == m.name
                    # determine whether the generator is being called from a kwbody method
                    sig = Base.unwrap_unionall(caller.sig)
                    cname, cmod = String(sig.parameters[1].name.name), caller.module
                    cparamrepr = map(repr, Iterators.drop(sig.parameters, 1))
                    csigstr = tuplestring(cparamrepr)
                    mkwc = match(kwbodyrex, cname)
                    if mkwc === nothing
                        getgen = "typeof(which($cmod.$(caller.name),$csigstr).generator.gen)"
                        add_if_evals!(pc[topmodname], topmod, getgen, paramrepr, tt; check_eval=check_eval)
                    else
                        if VERSION >= v"1.4.0-DEV.215"
                            getgen = "which(Core.kwfunc($cmod.$(mkwc.captures[1])),$csigstr).generator.gen"
                            ret = handle_kwbody(topmod, caller, cparamrepr, tt; check_eval = check_eval) #, getgen)
                            if ret !== nothing
                                push!(pc[topmodname], ret)
                            end
                        else
                            # Bail and treat as if anonymous
                            prefix = "isdefined($mmod, Symbol(\"$mname\")) && "
                            fstr = "getfield($mmod, Symbol(\"$mname\"))"  # this is universal, var is Julia 1.3+
                            add_if_evals!(pc[topmodname], topmod, fstr, paramrepr, tt; prefix=prefix, check_eval=check_eval)
                        end
                    end
                    break
                end
            end
        elseif isanon
            # Anonymous function, wrap in an `isdefined`
            prefix = "isdefined($mmod, Symbol(\"$mname\")) && "
            fstr = "getfield($mmod, Symbol(\"$mname\"))"  # this is universal, var is Julia 1.3+
            add_if_evals!(pc[topmodname], topmod, fstr, paramrepr, tt; prefix=prefix, check_eval = check_eval)
        else
            add_if_evals!(pc[topmodname], topmod, reprcontext(topmod, p), paramrepr, tt, check_eval = check_eval)
        end
    end

    # loop over the output
    for mod in keys(pc)
        # exclusions remover
        if remove_exclusions
            pc[mod] = exclusions_remover!(pc[mod], exclusions)
        end
    end
    return Dict(mod=>collect(lines) for (mod, lines) in pc) # convert Set to Array before return
end

"""
    exclusions_remover!(pcI, exclusions)

Search and removes terms appearing in `exclusions` from `pcI`.

By default it considers some strings as exclusions such as `r"\\bMain\\b"`.

# Examples
```julia
exclusions = Set(["hi","bye"])
pcI = Set(["good","bad","hi","bye","no"])

SnoopCompile.exclusions_remover!(pcI, exclusions)
```
"""
function exclusions_remover!(pcI::AbstractSet, exclusions)
    all_exclusions = union(exclusions, default_exclusions)

    # We can't just use `setdiff!` because this is a substring search
    todelete = Set{eltype(pcI)}()
    for line in pcI
        if any(occursin.(all_exclusions, line))
            push!(todelete, line)
        end
    end
    return setdiff!(pcI, todelete)
end

# These are found by running `exhaustive_remover!` on some packages
const default_exclusions = Set([
    r"\bMain\b",
])


function collect_per_method_inference_timings(snoopi_results::Vector, init_commands)
    outd = Dict{Any, Float64}()
    for snoopi_row in snoopi_results
        timings = collect_per_method_inference_timings(snoopi_row, init_commands)

        (total_time, root, mi_dep_graph) = snoopi_row
        @info "Total snoopi: $total_time\tSum all elements:$(sum(values(timings)))"
        display(timings)
        merge!(outd, timings)
    end
    @info "Returning merged results:"
    outd
end
function collect_per_method_inference_timings(snoopi_row, init_commands)
    (total_time, root, mi_dep_graph) = snoopi_row
    tt_deps = [a.specTypes => b.specTypes for (a,b) in mi_dep_graph]

    return per_method_instance_timings(init_commands, root.specTypes, tt_deps)
end

#struct Node{T}
#    key::T
#    children::Vector{Node{T}}
#    Node(key::T) where T = new{T}(key, Node{T}[])
#    Node{T}(key::T) where T = new{T}(key, Node{T}[])
#end
Node(root) = (; key=root, parents=Any[])
function per_method_instance_timings(init_commands, root, edges)
    #NT = fieldtype(eltype(edges)::Type{<:Union{Pair,Tuple}}, 1)
    NT = Any

    # 😮 It appears that currently edges can have a lot of duplicates!
    # Both exact duplicate edges, as well as multiple paths to the same node!
    # We only want to time each node once, so we have to do some cleanup.

    # First, let's deduplicate identical edges.
    edges = unique(edges)
    uniq_edges = edges

    # Next, since we only care about the bottom-up paths through the tree, we'll build a
    # tree with only parent edges, and collect all the leaves. We'll later traverse the
    # tree bottom up starting from the leaves, and use a seen-Set to skip duplicates and
    # time each node exactly once.

    meth_instances = unique(Iterators.flatten(edges))

    # Start with all nodes as leaves
    leaves = Set(meth_instances)
    delete!(leaves, root)

    #nodes = Dict{NT,Any}(m => Node(m) for m in meth_instances)

    # Build the tree by adding elements from the edges, and when we see a node as a caller,
    # we remove it from leaves.
    # Dict points from elements to their parents.
    reverse_graph_dict = Dict{NT,Vector{NT}}(root=>NT[])  # The root has no parents.
    for (k,v) in uniq_edges
        if k in leaves
            delete!(leaves, k)
        end
        #knode = nodes[k]
        #vnode = nodes[v]
        #push!(vnode.parents, knode)
        push!(get!(reverse_graph_dict, v, NT[]), k)
    end

    @info "Root: $root"
    @info "Collecting timings for $(length(meth_instances)) MethodInstances, with $(length(uniq_edges)) edges."

    # Now start timing how long it takes to compile each of them starting from the bottom
    # working the way up.
    # Do this timing measurement in a different process so that the functions will be
    # compiled fresh.
    tree_f, timings_f = tempname(), tempname()
    serialize(tree_f, (leaves, reverse_graph_dict))
    _measure_inference_timings(init_commands, tree_f, timings_f)
    return deserialize(timings_f)
end


function _measure_inference_timings(init_commands, infilename, outfilename, flags = String[])
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
        let
            # First, run user-defined commands to load the namespace
            Core.eval(Main, $(QuoteNode(init_commands)))

            # Load the serialized results
            (leaves, reverse_graph_dict) = deserialize($infilename)

            # warm up type inference machinery:
            let
                foo(x,y) = (x,y)
                _ = code_typed(Tuple{foo, Int,Int})
            end


            # Then, run the timings
            function time_all_nodes(node::Type, graph::Dict, seen::Set, out_times::Dict)
                if node in seen
                    return
                end
                push!(seen, node)
                time_type_inference(node, out_times)
                # TODO(PR): Switch to breadth-first search instead of function calls to avoid
                # stackoverflow (also b/c this is doing depth-first seaerch!)
                for p in graph[node]
                    time_all_nodes(p, graph, seen, out_times)
                end
            end
            function time_type_inference(tt::Type, out_times::Dict)
                _, time = @timed precompile(tt)
                out_times[tt] = time
            end

            out_times = Dict{Any, Float64}()
            seen = Set{Type}()

            for leaf in leaves
                time_all_nodes(leaf, reverse_graph_dict, seen, out_times)
            end
            serialize($outfilename, out_times)
        end
        exit()
    end)
    wait(process)
    println("done.")
    nothing
end
