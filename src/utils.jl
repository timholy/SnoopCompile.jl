function reprcontext(mod::Module, @nospecialize(T))
    # First check whether supplying module context allows evaluation
    rplain = repr(T; context=:module=>mod)
    try
        ex = Meta.parse(rplain)
        Core.eval(mod, ex)
        return rplain
    catch
        # Add full module context
        return repr(T; context=:module=>nothing)
    end
end

let known_type_cache = IdDict{Tuple{Module,Tuple{Vararg{Symbol}},Symbol},Bool}()
    global known_type
    """
        known_type(mod::Module, T::Union{Type,TypeVar})

    Returns `true` if the type `T` is "known" to the module `mod`, meaning that one could have written
    a function `f(x::T) = ...` in `mod` without getting an error.
    """
    function known_type(mod::Module, @nospecialize(T::Union{Type,TypeVar}))
        function startswith(@nospecialize(a::Tuple{Vararg{Symbol}}), @nospecialize(b::Tuple{Vararg{Symbol}}))
            length(b) >= length(a) || return false
            for i = 1:length(a)
                a[i] == b[i] || return false
            end
            return true
        end
        function firstname(@nospecialize(tpath::Tuple{Vararg{Symbol}}))
            i = 1
            while i <= length(tpath)
                sym = tpath[i]
                sym === :Main || return sym
                i += 1
            end
            return :ISNOTAMODULENAME
        end
        strippedname(tn::Core.TypeName) = Symbol(string(tn.name)[2:end])

        if isa(T, TypeVar)
            return known_type(mod, T.ub) && known_type(mod, T.lb)
        end
        T === Union{} && return true
        T = Base.unwrap_unionall(T)
        if isa(T, Union)
            return known_type(mod, T.a) & known_type(mod, T.b)
        end
        T = T::DataType
        tn = T.name
        tpath = fullname(tn.module)
        key = (mod, tpath, tn.name)
        kt = get(known_type_cache, key, nothing)
        if kt === nothing
            kt = startswith(fullname(mod), tpath) ||
                 ccall(:jl_get_module_of_binding, Ptr{Cvoid}, (Any, Any), mod, firstname(tpath)) != C_NULL ||
                 (isdefined(mod, tn.name) && (T2 = getfield(mod, tn.name); isa(T2, Type) && Base.unwrap_unionall(T2) === T)) ||
                 (T <: Function && isdefined(mod, strippedname(tn)) && (f = getfield(mod, strippedname(tn)); typeof(f) === T))
            known_type_cache[key] = kt
        end
        kt === false && return false
        for p in T.parameters
            isa(p, Type) || continue
            known_type(mod, p) || return false
        end
        return true
    end
end

function add_repr!(list, modgens::Dict{Module, Vector{Method}}, mi::MethodInstance, topmod::Module=mi.def.module; check_eval::Bool, time=nothing, suppress_time::Bool=false, kwargs...)
    # Create the string representation of the signature
    # Use special care with keyword functions, anonymous functions
    tt = Base.unwrap_unionall(mi.specTypes)
    m = mi.def
    p = tt.parameters[1]   # the portion of the signature related to the function itself
    paramrepr = map(T->reprcontext(topmod, T), Iterators.drop(tt.parameters, 1))  # all the rest of the args

    if any(str->occursin('#', str), paramrepr)
        @debug "Skipping $tt due to argument types having anonymous bindings"
        return false
    end
    mname, mmod = String(Base.unwrap_unionall(p).name.name), m.module   # m.name strips the kw identifier
    mkw = match(kwrex, mname)
    mkwbody = match(kwbodyrex, mname)
    isgen = match(genrex, mname) !== nothing
    isanon = match(anonrex, mname) !== nothing || match(innerrex, mname) !== nothing
    isgen && (mkwbody = nothing)
    if mkw !== nothing
        # Keyword function
        fname = mkw.captures[1] === nothing ? mkw.captures[2] : mkw.captures[1]
        fkw = "Core.kwftype(typeof($fname))"
        return add_if_evals!(list, topmod, fkw, paramrepr, tt; check_eval, time, suppress_time)
    elseif mkwbody !== nothing
        ret = handle_kwbody(topmod, m, paramrepr, tt; check_eval, kwargs...)
        if ret !== nothing
            push!(list, append_time(ret, time))
            return true
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
                    getgen = "typeof(which($(caller.name),$csigstr).generator.gen)"
                    return add_if_evals!(list, topmod, getgen, paramrepr, tt; check_eval, time, suppress_time)
                else
                    getgen = "which(Core.kwfunc($(mkwc.captures[1])),$csigstr).generator.gen"
                    ret = handle_kwbody(topmod, caller, cparamrepr, tt; check_eval = check_eval, kwargs...) #, getgen)
                    if ret !== nothing
                        push!(list, append_time(ret, time))
                        return true
                    end
                end
                break
            end
        end
    elseif isanon
        # Anonymous function, wrap in an `isdefined`
        prefix = "isdefined($mmod, Symbol(\"$mname\")) && "
        fstr = "getfield($mmod, Symbol(\"$mname\"))"  # this is universal, var is Julia 1.3+
        return add_if_evals!(list, topmod, fstr, paramrepr, tt; prefix, check_eval, time, suppress_time)
    end
    return add_if_evals!(list, topmod, reprcontext(topmod, p), paramrepr, tt; check_eval, time, suppress_time)
end

function handle_kwbody(topmod::Module, m::Method, paramrepr, tt, fstr="fbody"; check_eval = true)
    nameparent = Symbol(match(r"^#([^#]*)#", String(m.name)).captures[1])
    if !isdefined(m.module, nameparent)
        @debug "Module $topmod: skipping $m due to inability to look up kwbody parent" # see example related to issue #237
        return nothing
    end
    fparent = getfield(m.module, nameparent)
    pttstr = tuplestring(paramrepr[m.nkw+2:end])
    whichstr = "which($nameparent, $pttstr)"
    can1, exc1 = can_eval(topmod, whichstr, check_eval)
    if can1
        ttstr = tuplestring(paramrepr)
        pcstr = """
            let fbody = try Base.bodyfunction($whichstr) catch missing end
                if !ismissing(fbody)
                    precompile($fstr, $ttstr)
                end
            end"""
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

tupletypestring(params) = "Tuple{" * join(params, ',') * '}'
tupletypestring(fstr::AbstractString, params::AbstractVector{<:AbstractString}) =
    tupletypestring([fstr; params])

tuplestring(params) = isempty(params) ? "()" : '(' * join(params, ',') * ",)"

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

"""
     add_if_evals!(pclist, mod::Module, fstr, params, tt; prefix = "", check_eval::Bool=true)

Adds the precompilation statements only if they can be evaled. It uses [`can_eval`](@ref) internally.

In some cases, you may want to bypass this function by passing `check_eval=true` to increase the snooping performance.
"""
function add_if_evals!(pclist, mod::Module, fstr, params, tt; prefix = "", check_eval::Bool=true, time=nothing, suppress_time::Bool=false)
    ttstr = tupletypestring(fstr, params)
    can, exc = can_eval(mod, ttstr, check_eval)
    if can
        str = prefix*wrap_precompile(ttstr)
        if !suppress_time
            str = append_time(str, time)
        end
        push!(pclist, str)
        return true
    else
        @debug "Module $mod: skipping $tt due to eval failure" exception=exc _module=mod _file="precompile_$mod.jl"
    end
    return false
end


append_time(str, ::Nothing) = str
append_time(str, t::AbstractFloat) = str * "   # time: " * string(Float32(t))

wrap_precompile(ttstr::AbstractString) = "Base.precompile(" * ttstr * ')' # use `Base.` to avoid conflict with Core and Pkg

const default_exclusions = Set([
    r"\bMain\b",
])

function split2(str, on)
    i = findfirst(isequal(on), str)
    i === nothing && return str, ""
    return (SubString(str, firstindex(str), prevind(str, first(i))),
            SubString(str, nextind(str, last(i))))
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
