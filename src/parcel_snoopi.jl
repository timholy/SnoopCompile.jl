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

# === @snoopi_deep helper functions ========================================================

"""
    flatten_times(timing::Core.Compiler.Timings.Timing; tmin_secs = 0.0)

Flatten the execution graph of Timings returned from `@snoopi_deep` into a Vector of pairs,
with the exclusive time for each invcation of type inference within the compiler, sorted by
the exclusive time.
"""
function flatten_times(timing::Core.Compiler.Timings.Timing; tmin_secs = 0.0)
    out = Any[]
    frontier = [timing]
    while !isempty(frontier)
        t = popfirst!(frontier)
        exclusive_time = (t.time / 1e9)
        if exclusive_time >= tmin_secs
            push!(out, exclusive_time => t.mi_info)
        end
        for c in t.children
            push!(frontier, c)
        end
    end
    return sort(out; by=tl->tl[1])
end


import FlameGraphs

using Base.StackTraces: StackFrame
using LeftChildRightSiblingTrees: Node, addchild
using Core.Compiler.Timings: Timing

struct InclusiveTiming
    mi_info::Core.Compiler.Timings.InferenceFrameInfo
    inclusive_time::UInt64
    start_time::UInt64
    children::Vector{InclusiveTiming}
end

inclusive_time(t::InclusiveTiming) = t.inclusive_time

function build_inclusive_times(t::Timing)
    child_times = InclusiveTiming[
        build_inclusive_times(child)
        for child in t.children
    ]
    incl_time = t.time + sum(inclusive_time.(child_times); init=UInt64(0))
    return InclusiveTiming(t.mi_info, incl_time, t.start_time, child_times)
end

"""
    to_flamegraph(t::Core.Compiler.Timings.Timing; tmin_secs=0.0)

Convert the call tree of inference timings returned from `@snoopi_deep` into a FlameGraph.
Returns a FlameGraphs.FlameGraph structure that represents the timing trace recorded for
type inference.

Frames that take less than `tmin_secs` seconds of _inclusive time_ will not be included
in the resultant FlameGraph (meaning total time including it and all of its children).
"""
function to_flamegraph(t::Timing; tmin_secs = 0.0)
    it = build_inclusive_times(t)
    to_flamegraph(it; tmin_secs=tmin_secs)
end

function to_flamegraph(to::InclusiveTiming; tmin_secs = 0.0)
    tmin_ns = UInt64(round(tmin_secs * 1e9))

    # Compute a "root" frame for the top-level node, to cover the whole profile
    node_data = _flamegraph_frame(to, to.start_time; toplevel=true)
    root = Node(node_data)
    return _build_flamegraph!(root, to, to.start_time, tmin_ns)
end
function _build_flamegraph!(root, to::InclusiveTiming, start_ns, tmin_ns)
    for child in to.children
        if child.inclusive_time > tmin_ns
            node_data = _flamegraph_frame(child, start_ns; toplevel=false)
            node = addchild(root, node_data)
            _build_flamegraph!(node, child, start_ns, tmin_ns)
        end
    end
    return root
end

function frame_name(mi_info::Core.Compiler.Timings.InferenceFrameInfo)
    frame_name(mi_info.mi::Core.Compiler.MethodInstance)
end
function frame_name(mi::Core.Compiler.MethodInstance)
    frame_name(mi.def.name, mi.specTypes)
end
# Special printing for Type Tuples so they're less ugly in the FlameGraph
function frame_name(name, ::Type{TT}) where TT<:Tuple
    #try
        io = IOBuffer()
        Base.show_tuple_as_call(io, name, TT)
        v = String(take!(io))
        return v
    #catch  # TODO: Narrow this to only swallowing the expected exception type
    #    # Some Type Tuples apparently cannot be printed to a string?
    #    return name
    #end
end

# NOTE: The "root" node doesn't cover th whole profile, because it's only the _complement_
# of the inference times (so it's missing the _overhead_ from the measurement).
# SO we need to manually create a root node that covers the whole thing.
function max_end_time(t::InclusiveTiming)
    return maximum(child.start_time + child.inclusive_time for child in t.children;
                    init = UInt64(t.start_time + t.inclusive_time))
end

# Make a flat frame for this Timing
function _flamegraph_frame(to::InclusiveTiming, start_ns; toplevel)
    # TODO: Use a better conversion to a StackFrame so this contains the right kind of data
    mi = to.mi_info.mi
    tt = Symbol(frame_name(to.mi_info))
    sf = StackFrame(tt, mi.def.file, mi.def.line, mi, false, false, UInt64(0x0))
    status = 0x0  # "default" status -- See FlameGraphs.jl
    start = to.start_time - start_ns
    if toplevel
        # Compute a range over the whole profile for the top node.
        range = Int(start) : max_end_time(to) - start_ns
    else
        range = Int(start) : Int(start + to.inclusive_time)
    end
    return FlameGraphs.NodeData(sf, status, range)
end

