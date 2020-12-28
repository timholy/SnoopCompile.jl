import FlameGraphs

using Base.StackTraces: StackFrame
using FlameGraphs.LeftChildRightSiblingTrees: Node, addchild
using FlameGraphs.AbstractTrees
using Core.Compiler.Timings: InferenceFrameInfo
using SnoopCompileCore: InferenceTiming, InferenceTimingNode, inclusive, exclusive
using Profile
using Cthulhu

const InferenceNode = Union{InferenceFrameInfo,InferenceTiming,InferenceTimingNode}

const flamegraph = FlameGraphs.flamegraph  # For re-export

Core.MethodInstance(mi_info::InferenceFrameInfo) = mi_info.mi
Core.MethodInstance(t::InferenceTiming) = MethodInstance(t.mi_info)
Core.MethodInstance(t::InferenceTimingNode) = MethodInstance(t.mi_timing)

Core.Method(x::InferenceNode) = MethodInstance(x).def::Method   # deliberately throw an error if this is a module

isROOT(mi::MethodInstance) = mi === Core.Compiler.Timings.ROOTmi
isROOT(m::Method) = m === Core.Compiler.Timings.ROOTmi.def
isROOT(mi_info::InferenceNode) = isROOT(MethodInstance(mi_info))

# Record instruction pointers we've already looked up (performance optimization)
const lookups = Dict{Union{Ptr{Nothing}, Core.Compiler.InterpreterIP}, Vector{StackTraces.StackFrame}}()

# These should be in SnoopCompileCore, except that it promises not to specialize Base methods
Base.show(io::IO, t::InferenceTiming) = (print(io, "InferenceTiming: "); _show(io, t))
_show(io::IO, t::InferenceTiming) = print(io, exclusive(t), '/', inclusive(t), " on ", t.mi_info)

function Base.show(io::IO, node::InferenceTimingNode)
    print(io, "InferenceTimingNode: ")
    _show(io, node.mi_timing)
    print(io, " with ", length(node.children), " direct children")
end

"""
    flatten(timing; tmin = 0.0, sortby=exclusive)

Flatten the execution graph of `InferenceTimingNode`s returned from `@snoopi_deep` into a Vector of `InferenceTiming`
frames, each encoding the time needed for inference of a single `MethodInstance`.
By default, results are sorted by `exclusive` time (the time for inferring the `MethodInstance` itself, not including
any inference of its callees); other options are `sortedby=inclusive` which includes the time needed for the callees,
or `nothing` to obtain them in the order they were inferred (depth-first order).

`ROOT` is a dummy element whose time corresponds to the sum of time spent outside inference. It's
the total time of the operation minus the total time for inference.

# Example


"""
function flatten(timing::InferenceTimingNode; tmin = 0.0, sortby::Union{typeof(exclusive),typeof(inclusive),Nothing}=exclusive)
    out = InferenceTiming[]
    flatten!(sortby === nothing ? exclusive : sortby, out, timing, tmin)
    return sortby===nothing ? out : sort(out; by=sortby)
end

function flatten!(gettime::Union{typeof(exclusive),typeof(inclusive)}, out, timing, tmin)
    time = gettime(timing)
    if time >= tmin
        push!(out, timing.mi_timing)
    end
    for child in timing.children
        flatten!(gettime, out, child, tmin)
    end
    return out
end

"""
    accumulate_by_source(flattened; tmin = 0.0, by=exclusive)

Add the inference timings for all `MethodInstance`s of a single `Method` together.
`flattened` is the output of [`flatten`](@ref).
Returns a list of `(t, method)` tuples.

When the accumulated time for a `Method` is large, but each instance is small, it indicates
that it is being inferred for many specializations (which might include specializations with different constants).

# Example

```julia
julia> tinf = @snoopi_deep sort(Float16[1, 2, 3]);

julia> tm = accumulate_by_source(flatten(tinf); tmin=0.0005)
6-element Vector{Tuple{Float64, Method}}:
 (0.000590579, _copyto_impl!(dest::Array, doffs::Integer, src::Array, soffs::Integer, n::Integer) in Base at array.jl:307)
 (0.000616788, partition!(v::AbstractVector{T} where T, lo::Integer, hi::Integer, o::Base.Order.Ordering) in Base.Sort at sort.jl:578)
 (0.000634394, sort!(v::AbstractVector{T} where T, lo::Integer, hi::Integer, ::Base.Sort.InsertionSortAlg, o::Base.Order.Ordering) in Base.Sort at sort.jl:527)
 (0.000720815, Vector{T}(::UndefInitializer, m::Int64) where T in Core at boot.jl:448)
 (0.001157551, getindex(::Type{T}, x, y, z) where T in Base at array.jl:394)
 (0.046509861, ROOT() in Core.Compiler.Timings at compiler/typeinfer.jl:75)
```

`ROOT` is a dummy element whose time corresponds to the sum of time spent on everything *except* inference.
"""
function accumulate_by_source(::Type{M}, flattened::Vector{InferenceTiming}; tmin = 0.0, by::Union{typeof(exclusive),typeof(inclusive)}=exclusive) where M<:Union{Method,MethodInstance}
    tmp = Dict{Union{M,MethodInstance},Float64}()
    for frame in flattened
        mi = MethodInstance(frame)
        m = mi.def
        if M === Method && isa(m, Method)
            tmp[m] = get(tmp, m, 0.0) + by(frame)
        else
            tmp[mi] = by(frame)    # module-level thunks are stored verbatim
        end
    end
    return sort([(t, m) for (m, t) in tmp if t >= tmin]; by=first)
end

accumulate_by_source(flattened::Vector{InferenceTiming}; kwargs...) = accumulate_by_source(Method, flattened; kwargs...)

## parcel and supporting infrastructure

function isprecompilable(mi::MethodInstance; excluded_modules=Set([Main::Module]))
    m = mi.def
    if isa(m, Method)
        mod = m.module
        can_eval = excluded_modules === nothing || mod ∉ excluded_modules
        if can_eval
            params = Base.unwrap_unionall(mi.specTypes)::DataType
            for p in params.parameters
                if p isa TypeVar
                    if !known_type(mod, p.ub) || !known_type(mod, p.lb)
                        can_eval = false
                        break
                    end
                elseif p isa Type
                    if !known_type(mod, p)
                        can_eval = false
                        break
                    end
                end
            end
        end
        return can_eval
    end
    return false
end

struct Precompiles
    mi_info::InferenceFrameInfo                           # entrance point to inference (the "root")
    total_time::Float64                                   # total time for the root
    precompiles::Vector{Tuple{Float64,MethodInstance}}    # list of precompilable child MethodInstances with their times
end
Precompiles(node::InferenceTimingNode) = Precompiles(InferenceTiming(node).mi_info, inclusive(node), Tuple{Float64,MethodInstance}[])

Core.MethodInstance(pc::Precompiles) = MethodInstance(pc.mi_info)
SnoopCompileCore.inclusive(pc::Precompiles) = pc.total_time
precompilable_time(precompiles::Vector{Tuple{Float64,MethodInstance}}) where T = sum(first, precompiles; init=0.0)
precompilable_time(precompiles::Dict{MethodInstance,T}) where T = sum(values(precompiles); init=zero(T))
precompilable_time(pc::Precompiles) = precompilable_time(pc.precompiles)

function Base.show(io::IO, pc::Precompiles)
    tpc = precompilable_time(pc)
    print(io, "Precompiles: ", pc.total_time, " for ", MethodInstance(pc),
              " had ", length(pc.precompiles), " precompilable roots reclaiming ", tpc,
              " ($(round(Int, 100*tpc/pc.total_time))%)")
end

function precompilable_roots!(pc, node::InferenceTimingNode, tthresh; excluded_modules=Set([Main::Module]))
    (t = inclusive(node)) >= tthresh || return pc
    mi = MethodInstance(node)
    if isprecompilable(mi; excluded_modules)
        push!(pc.precompiles, (t, mi))
        return pc
    end
    foreach(node.children) do c
        precompilable_roots!(pc, c, tthresh; excluded_modules=excluded_modules)
    end
    return pc
end

function precompilable_roots(node::InferenceTimingNode, tthresh; kwargs...)
    pcs = [precompilable_roots!(Precompiles(child), child, tthresh; kwargs...) for child in node.children if inclusive(node) >= tthresh]
    t_grand_total = sum(inclusive, node.children)
    tpc = precompilable_time.(pcs)
    p = sortperm(tpc)
    return (t_grand_total, pcs[p])
end

function parcel((t_grand_total,pcs)::Tuple{Float64,Vector{Precompiles}})
    # Because the same MethodInstance can be compiled multiple times for different Const values,
    # we just keep the largest time observed per MethodInstance.
    pcdict = Dict{Module,Dict{MethodInstance,Float64}}()
    for pc in pcs
        for (t, mi) in pc.precompiles
            m = mi.def
            mod = isa(m, Method) ? m.module : m
            pcmdict = get!(Dict{MethodInstance,Float64}, pcdict, mod)
            pcmdict[mi] = max(t, get(pcmdict, mi, zero(Float64)))
        end
    end
    pclist = [mod => (precompilable_time(pcmdict), sort!([(t, mi) for (mi, t) in pcmdict]; by=first)) for (mod, pcmdict) in pcdict]
    sort!(pclist; by = pr -> pr.second[1])
    return t_grand_total, pclist
end

function parcel(t::InferenceTimingNode; tmin=0.0, kwargs...)
    parcel(precompilable_roots(t, tmin; kwargs...))
end

### write

function get_reprs(tmi::Vector{Tuple{Float64,MethodInstance}}; tmin=0.001)
    strs = OrderedSet{String}()
    modgens = Dict{Module, Vector{Method}}()
    tmp = String[]
    twritten = 0.0
    for (t, mi) in reverse(tmi)
        if t >= tmin
            if add_repr!(tmp, modgens, mi; check_eval=false, time=t)
                str = pop!(tmp)
                if !any(rex -> occursin(rex, str), default_exclusions)
                    push!(strs, str)
                    twritten += t
                end
            end
        end
    end
    return strs, twritten
end

function write(io::IO, tmi::Vector{Tuple{Float64,MethodInstance}}; indent::AbstractString="    ", kwargs...)
    strs, twritten = get_reprs(tmi; kwargs...)
    for str in strs
        println(io, indent, str)
    end
    return twritten, length(strs)
end

function write(prefix::AbstractString, pc::Vector{Pair{Module,Tuple{Float64,Vector{Tuple{Float64,MethodInstance}}}}}; ioreport::IO=stdout, header::Bool=true, always::Bool=false, kwargs...)
    if !isdir(prefix)
        mkpath(prefix)
    end
    for (mod, ttmi) in pc
        tmod, tmi = ttmi
        v, twritten = get_reprs(tmi; kwargs...)
        if isempty(v)
            println(ioreport, "$mod: no precompile statements out of $tmod")
            continue
        end
        open(joinpath(prefix, "precompile_$(mod).jl"), "w") do io
            if header
                if any(str->occursin("__lookup", str), v)
                    println(io, lookup_kwbody_str)
                end
                println(io, "function _precompile_()")
                !always && println(io, "    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing")
            end
            for ln in v
                println(io, "    ", ln)
            end
            header && println(io, "end")
        end
        println(ioreport, "$mod: precompiled $twritten out of $tmod")
    end
end

## Profile-guided de-optimization

# These tools can help balance the need for specialization (to achieve good runtime performance)
# against the desire to reduce specialization to reduce latency.

struct MethodLoc
    func::Symbol
    file::Symbol
    line::Int
end
MethodLoc(sf::StackTraces.StackFrame) = MethodLoc(sf.func, sf.file, sf.line)

Base.show(io::IO, ml::MethodLoc) = print(io, ml.func, " at ", ml.file, ':', ml.line, " [inlined and pre-inferred]")

"""
    ridata = runtime_inferencetime(tinf::InferenceTimingNode)
    ridata = runtime_inferencetime(tinf::InferenceTimingNode, profiledata; lidict)

Compare runtime and inference-time on a per-method basis. `ridata[m::Method]` returns `(trun, tinfer, nspecializations)`,
measuring the approximate amount of time spent running `m`, inferring `m`, and the number of type-specializations, respectively.
`trun` is estimated from profiling data, which the user is responsible for capturing before the call.
Typically `tinf` is collected via `@snoopi_deep` on the first call (in a fresh session) to a workload,
and the profiling data collected on a subsequent call. In some cases you may want to repeat the workload
several times to collect enough profiling samples.

`profiledata` and `lidict` are obtained from `Profile.retrieve()`.
"""
function runtime_inferencetime(tinf::InferenceTimingNode; kwargs...)
    pdata, lidict = Profile.retrieve()
    return runtime_inferencetime(tinf, pdata; lidict=lidict, kwargs...)
end
function runtime_inferencetime(tinf::InferenceTimingNode, pdata; lidict, consts::Bool=true, delay=ccall(:jl_profile_delay_nsec, UInt64, ())/10^9)
    lilist, nsamples, nselfs, totalsamples = Profile.parse_flat(StackTraces.StackFrame, pdata, lidict, false)
    tf = flatten(tinf)
    tm = accumulate_by_source(tf)
    # MethodInstances that get inlined don't have the linfo field. Guess the method from the name/line/file.
    # Filenames are complicated because of variations in how paths are encoded, especially for methods in Base & stdlibs.
    methodlookup = Dict{Tuple{Symbol,Int},Vector{Pair{String,Method}}}()  # (func, line) => [file => method]
    for (_, m) in tm
        fm = get!(Vector{Pair{String,Method}}, methodlookup, (m.name, Int(m.line)))
        push!(fm, string(m.file) => m)
    end

    function matchloc(loc::MethodLoc)
        fm = get(methodlookup, (loc.func, Int(loc.line)), nothing)
        fm === nothing && return loc
        meths = Set{Method}()
        locfile = string(loc.file)
        for (f, m) in fm
            endswith(locfile, f) && push!(meths, m)
        end
        length(meths) == 1 && return pop!(meths)
        return loc
    end
    matchloc(sf::StackTraces.StackFrame) = matchloc(MethodLoc(sf))

    ridata = Dict{Union{Method,MethodLoc},Tuple{Float64,Float64,Int}}()
    # Insert the profiling data
    for (sf, nself) in zip(lilist, nselfs)
        mi = sf.linfo
        m = isa(mi, MethodInstance) ? mi.def : matchloc(sf)
        if isa(m, Method) || isa(m, MethodLoc)
            trun, tinfer, nspecializations = get(ridata, m, (0.0, 0.0, 0))
            ridata[m] = (trun + nself*delay, tinfer, nspecializations)
        else
            @show typeof(m) m
            error("whoops")
        end
    end
    @assert all(ttn -> ttn[2] == 0.0, values(ridata))
    # Now add inference times & specialization counts. To get the counts we go back to tf rather than using tm.
    if !consts
        tf = accumulate_by_source(MethodInstance, tf)
    end
    for frame in tf
        t = exclusive(frame)
        isROOT(frame) && continue
        m = MethodInstance(frame).def
        if isa(m, Method)
            trun, tinfer, nspecializations = get(ridata, m, (0.0, 0.0, 0))
            ridata[m] = (trun, tinfer + t, nspecializations + 1)
        end
    end
    # Sort the outputs to try to prioritize opportunities for the developer. Because we have multiple objectives (fast runtime
    # and fast compile time), there's no unique sorting order, nor can we predict the cost to runtime performance of reducing
    # the method specialization. Here we use the following approximation: we naively estimate "what the inference time could be" if
    # there were only one specialization of each method, and the answers are sorted by the estimated savings. This does not
    # even attempt to account for any risk to the runtime. For any serious analysis, looking at the scatter plot with
    # [`specialization_plot`](@ref) is recommended.
    savings((trun, tinfer, nspec)::Tuple{Float64,Float64,Int}) = tinfer * (nspec - 1)
    savings(pr::Pair) = savings(pr.second)
    return sort(collect(ridata); by=savings)
end

## Analysis of inference triggers

"""
    InferenceTrigger(callee::MethodInstance, callerframes::Vector{StackFrame}, btidx::Int, bt)

Organize information about the "triggers" of inference. `callee` is the `MethodInstance` requiring inference,
`callerframes`, `btidx` and `bt` contain information about the caller.
`callerframes` are the frame(s) of call site that triggered inference; it's a `Vector{StackFrame}`, rather than a
single `StackFrame`, due to the possibility that the caller was inlined into something else, in which case the first entry
is the direct caller and the last entry corresponds to the MethodInstance into which it was ultimately inlined.
`btidx` is the index in `bt`, the backtrace collected upon entry into inference, corresponding to `callerframes`.

See also: [`callerinstance`](@ref) and [`callingframe`](@ref).
"""
struct InferenceTrigger
    callee::MethodInstance
    callerframes::Vector{StackTraces.StackFrame}
    btidx::Int   # callerframes = StackTraces.lookup(bt[btidx])
    bt::Vector{Union{Ptr{Nothing}, Core.Compiler.InterpreterIP}}
end

function Base.show(io::IO, itrig::InferenceTrigger)
    print(io, "Inference triggered to call ")
    printstyled(io, itrig.callee; color=:yellow)
    if !isempty(itrig.callerframes)
        sf = first(itrig.callerframes)
        print(io, " from ")
        printstyled(io, sf.func; color=:red, bold=true)
        print(io, " (",  sf.file, ':', sf.line, ')')
        caller = itrig.callerframes[end].linfo
        if isa(caller, MethodInstance)
            length(itrig.callerframes) == 1 ? print(io, " with specialization ") : print(io, " inlined into ")
            printstyled(io, caller; color=:blue)
            if length(itrig.callerframes) > 1
                sf = itrig.callerframes[end]
                print(io, " (",  sf.file, ':', sf.line, ')')
            end
        elseif isa(caller, Core.CodeInfo)
            print(io, " called from toplevel code ", caller)
        end
    else
        print(io, " called from toplevel")
    end
end

"""
    mi = callerinstance(itrig::InferenceTrigger)

Return the MethodInstance `mi` of the caller in the selected stackframe in `itrig`.
"""
callerinstance(itrig::InferenceTrigger) = itrig.callerframes[end].linfo

# Select the next (caller) frame that's a Julia (as opposed to C) frame; returns the stackframe and its index in bt, or nothing
function next_julia_frame(bt, idx)
    while idx < length(bt)
        ip = bt[idx+=1]
        sfs = get!(()->Base.StackTraces.lookup(ip), lookups, ip)
        sf = sfs[end]
        sf.from_c && continue
        mi = sf.linfo
        isa(mi, Core.MethodInstance) || continue
        m = mi.def
        isa(m, Method) || continue
        m.module === Core.Compiler && continue
        return sfs, idx
    end
    return nothing
end

"""
    itrigs = inference_triggers(tinf::InferenceTimingNode; exclude_toplevel=true)

Collect the "triggers" of inference, each a fresh entry into inference via a call dispatched at runtime.
All the entries in `itrigs` are previously uninferred, or are freshly-inferred for specific constant inputs.

`exclude_toplevel` determines whether calls made from the REPL, `include`, or test suites are excluded.

# Example

We collect data using the [`SnoopCompile.itrigs_demo`](@ref):

```julia
julia> tinf = SnoopCompile.itrigs_demo()
Core.Compiler.Timings.Timing(InferenceFrameInfo for Core.Compiler.Timings.ROOT()) with 2 children

julia> itrigs = inference_triggers(tinf)
2-element Vector{InferenceTrigger}:
 Inference triggered to call MethodInstance for double(::UInt8) from calldouble1 (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:762) inlined into MethodInstance for calldouble2(::Vector{Vector{Any}}) (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:763)
 Inference triggered to call MethodInstance for double(::Float64) from calldouble1 (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:762) inlined into MethodInstance for calldouble2(::Vector{Vector{Any}}) (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:763)
```
"""
function inference_triggers(tinf::InferenceTimingNode; exclude_toplevel::Bool=true)
    function first_julia_frame(bt)
        ret = next_julia_frame(bt, 1)
        if ret === nothing
            return StackTraces.StackFrame[], 0
        end
        return ret
    end

    itrigs = map(tinf.children) do child
        bt = child.bt
        bt === nothing && throw(ArgumentError("it seems you've supplied a child node, but backtraces are collected only at the entrance to inference"))
        InferenceTrigger(MethodInstance(child), first_julia_frame(bt)..., bt)
    end
    if exclude_toplevel
        filter!(maybe_internal, itrigs)
    end
    return itrigs
end

const rextest = r"stdlib.*Test.jl$"
function maybe_internal(itrig::InferenceTrigger)
    for sf in itrig.callerframes
        linfo = sf.linfo
        if isa(linfo, MethodInstance)
            m = linfo.def
            if isa(m, Method)
                m.module === Base && m.name === :include_string && return false
                m.name === :eval && return false
            end
        end
        match(rextest, string(sf.file)) !== nothing && return false
    end
    return true
end

"""
    itrigcaller = callingframe(itrig::InferenceTrigger)

"Step out" one layer of the stacktrace, referencing the caller of the current frame of `itrig`.

You can retrieve the proximal trigger of inference with `InferenceTrigger(itrigcaller)`.

# Example

We collect data using the [`SnoopCompile.itrigs_demo`](@ref):

```julia
julia> itrig = inference_triggers(SnoopCompile.itrigs_demo())[1]
Inference triggered to call MethodInstance for double(::UInt8) from calldouble1 (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:762) inlined into MethodInstance for calldouble2(::Vector{Vector{Any}}) (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:763)

julia> itrigcaller = callingframe(itrig)
Inference triggered to call MethodInstance for double(::UInt8) from calleach (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:764) with specialization MethodInstance for calleach(::Vector{Vector{Vector{Any}}})
```
"""
function callingframe(itrig::InferenceTrigger)
    idx = itrig.btidx
    if idx < length(itrig.bt)
        ret = next_julia_frame(itrig.bt, idx)
        if ret !== nothing
            return InferenceTrigger(itrig.callee, ret..., itrig.bt)
        end
    end
    return InferenceTrigger(itrig.callee, StackTraces.StackFrame[], length(itrig.bt)+1, itrig.bt)
end

"""
    itrig0 = InferenceTrigger(itrig::InferenceTrigger)

Reset an inference trigger to point to the stackframe that triggered inference.
This can be useful to undo the actions of [`callingframe`](@ref) and [`skiphigherorder`](@ref).
"""
InferenceTrigger(itrig::InferenceTrigger) = InferenceTrigger(itrig.callee, next_julia_frame(itrig.bt, 1)..., itrig.bt)


"""
    itrignew = skiphigherorder(itrig; exact::Bool=false)

Attempt to skip over frames of higher-order functions that take the callee as a function-argument.
This can be useful if you're analyzing inference triggers for an entire package and would prefer to assign
triggers to package-code rather than Base functions like `map!`, `broadcast`, etc.

# Example

We collect data using the [`SnoopCompile.itrigs_higherorder_demo`](@ref):

```julia
julia> itrig = inference_triggers(SnoopCompile.itrigs_higherorder_demo())[1]
Inference triggered to call MethodInstance for double(::Float64) from mymap! (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:706) with specialization MethodInstance for mymap!(::typeof(SnoopCompile.ItrigHigherOrderDemo.double), ::Vector{Any}, ::Vector{Any})

julia> callingframe(itrig)      # step out one (non-inlined) frame
Inference triggered to call MethodInstance for double(::Float64) from mymap (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:710) with specialization MethodInstance for mymap(::typeof(SnoopCompile.ItrigHigherOrderDemo.double), ::Vector{Any})

julia> skiphigherorder(itrig)   # step out to frame that doesn't have `double` as a function-argument
Inference triggered to call MethodInstance for double(::Float64) from callmymap (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:711) with specialization MethodInstance for callmymap(::Vector{Any})
```

!!! warn
    By default `skiphigherorder` is conservative, and insists on being sure that it's the callee being passed to the higher-order function.
    Higher-order functions that do not get specialized (e.g., with `::Function` argument types) will not be skipped over.
    You can pass `exact=false` to allow `::Function` to also be passed over, but keep in mind that this may falsely skip some frames.
"""
function skiphigherorder(itrig::InferenceTrigger; exact::Bool=true)
    ft = Base.unwrap_unionall(Base.unwrap_unionall(itrig.callee.specTypes).parameters[1])
    sfs, idx = itrig.callerframes, itrig.btidx
    while idx < length(itrig.bt)
        callermi = sfs[end].linfo
        if !hasparameter(callermi.specTypes, ft, exact)
            return InferenceTrigger(itrig.callee, sfs, idx, itrig.bt)
        end
        ret = next_julia_frame(itrig.bt, idx)
        ret === nothing && return InferenceTrigger(itrig.callee, sfs, idx, itrig.bt)
        sfs, idx = ret
    end
    return itrig
end

function hasparameter(@nospecialize(typ), @nospecialize(ft), exact::Bool)
    isa(typ, Type) || return false
    typ = Base.unwrap_unionall(typ)
    typ === ft && return true
    exact || (typ === Function && return true)
    typ === Union{} && return false
    if isa(typ, Union)
        hasparameter(typ.a, ft, exact) && return true
        hasparameter(typ.b, ft, exact) && return true
        return false
    end
    for p in typ.parameters
        hasparameter(p, ft, exact) && return true
    end
    return false
end

# Integrations
AbstractTrees.children(tinf::InferenceTimingNode) = tinf.children

InteractiveUtils.edit(itrig::InferenceTrigger) = edit(Location(itrig.callerframes[end]))
Cthulhu.descend(itrig::InferenceTrigger; kwargs...) = descend(callerinstance(itrig); kwargs...)
Cthulhu.instance(itrig::InferenceTrigger) = itrig.callee
Cthulhu.method(itrig::InferenceTrigger) = itrig.callee.def
Cthulhu.specTypes(itrig::InferenceTrigger) = Cthulhu.specTypes(itrig.callee)
Cthulhu.backedges(itrig::InferenceTrigger) = (itrig.callerframes,)
Cthulhu.nextnode(itrig::InferenceTrigger, edge) = (ret = callingframe(itrig); return isempty(ret.callerframes) ? nothing : ret)

struct Location  # essentially a LineNumberNode + function name
    func::Symbol
    file::Symbol
    line::Int
end
Location(sf::StackTraces.StackFrame) = Location(sf.func, sf.file, sf.line)
function Location(itrig::InferenceTrigger)
    isempty(itrig.callerframes) && return Location(:from_c, :from_c, 0)
    return Location(itrig.callerframes[1])
end

Base.show(io::IO, loc::Location) = print(io, loc.func, " at ", loc.file, ':', loc.line)
InteractiveUtils.edit(loc::Location) = edit(string(loc.file), loc.line)

struct LocationTrigger
    loc::Location
    itrigs::Vector{InferenceTrigger}
end

"""
    ncallees, ncallers = diversity(loctrigs::LocationTriggers)

Count the number of distinct MethodInstances among the callees and callers, respectively, at a particular code location.
"""
function diversity(loctrigs::LocationTrigger)
    # Analyze caller => callee argument type diversity
    callees, callers, ncextra = Set{MethodInstance}(), Set{MethodInstance}(), 0
    for itrig in loctrigs.itrigs
        push!(callees, itrig.callee)
        caller = itrig.callerframes[end].linfo
        if isa(caller, MethodInstance)
            push!(callers, caller)
        else
            ncextra += 1
        end
    end
    return length(callees), length(callers) + ncextra
end

function Base.show(io::IO, loctrigs::LocationTrigger)
    ncallees, ncallers = diversity(loctrigs)
    print(io, loctrigs.loc, " (", ncallees, " callees from ", ncallers, " callers)")
end

InteractiveUtils.edit(loctrig::LocationTrigger) = edit(loctrig.loc)

"""
    loctrigs = accumulate_by_source(itrigs::AbstractVector{InferenceTrigger})

Aggregate inference triggers by location (function, file, and line number) of the caller.

# Example

We collect data using the [`SnoopCompile.itrigs_demo`](@ref):

```julia
julia> itrigs = inference_triggers(SnoopCompile.itrigs_demo())
2-element Vector{InferenceTrigger}:
 Inference triggered to call MethodInstance for double(::UInt8) from calldouble1 (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:762) inlined into MethodInstance for calldouble2(::Vector{Vector{Any}}) (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:763)
 Inference triggered to call MethodInstance for double(::Float64) from calldouble1 (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:762) inlined into MethodInstance for calldouble2(::Vector{Vector{Any}}) (/pathto/SnoopCompile/src/parcel_snoopi_deep.jl:763)

julia> accumulate_by_source(itrigs)
1-element Vector{SnoopCompile.LocationTrigger}:
    calldouble1 at /pathto/SnoopCompile/src/parcel_snoopi_deep.jl:762 (2 callees from 1 callers)
```
"""
function accumulate_by_source(itrigs::AbstractVector{InferenceTrigger})
    cs = Dict{Location,Vector{InferenceTrigger}}()
    for itrig in itrigs
        loc = Location(itrig)
        itrigs_loc = get!(Vector{InferenceTrigger}, cs, loc)
        push!(itrigs_loc, itrig)
    end
    return sort([LocationTrigger(loc, itrigs_loc) for (loc, itrigs_loc) in cs]; by=loctrig->length(loctrig.itrigs))
end

## Flamegraph creation

"""
    flamegraph(t::Core.Compiler.Timings.Timing; tmin=0.0, excluded_modules=Set([Main]), mode=nothing)
    flamegraph(t::InclusiveTiming; tmin=0.0)

Convert the call tree of inference timings returned from `@snoopi_deep` into a FlameGraph.
Returns a FlameGraphs.FlameGraph structure that represents the timing trace recorded for
type inference.

Frames that take less than `tmin` seconds of _inclusive time_ will not be included
in the resultant FlameGraph (meaning total time including it and all of its children).
This can be helpful if you have a very big profile, to save on processing time.

Non-precompilable frames are marked in reddish colors. `excluded_modules` can be used to mark methods
defined in modules to which you cannot or do not wish to add precompiles.

`mode` controls how frames are named in tools like ProfileView.
`nothing` uses the default of just the qualified function name, whereas
supplying `mode=Dict(method => count)` counting the number of specializations of
each method will cause the number of specializations to be included in the frame name.

# Examples
```julia
julia> timing = @snoopi_deep begin
           @eval sort(rand(100))  # Evaluate some code and profile julia's type inference
       end;

julia> fg = flamegraph(timing)
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:70, 0x00, 0:15355670))

julia> ProfileView.view(fg);  # Display the FlameGraph in a package that supports it

julia> fg = flamegraph(timing; tmin=0.0001)  # Skip very tiny frames
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:70, 0x00, 0:15355670))
```
"""
function FlameGraphs.flamegraph(tinf::InferenceTimingNode; tmin = 0.0, excluded_modules=Set([Main::Module]), mode=nothing)
    io = IOBuffer()

    # Compute a "root" frame for the top-level node, to cover the whole profile
    node_data, _ = _flamegraph_frame(io, tinf, tinf.start_time, false, excluded_modules, mode; toplevel=true)
    root = Node(node_data)
    return _build_flamegraph!(root, io, tinf, tinf.start_time, tmin, true, excluded_modules, mode)
end
function _build_flamegraph!(root, io::IO, node::InferenceTimingNode, start_secs, tmin, check_precompilable, excluded_modules, mode)
    for child in node.children
        if inclusive(child) > tmin
            node_data, child_check_precompilable = _flamegraph_frame(io, child, start_secs, check_precompilable, excluded_modules, mode; toplevel=false)
            node = addchild(root, node_data)
            _build_flamegraph!(node, io, child, start_secs, tmin, child_check_precompilable, excluded_modules, mode)
        end
    end
    return root
end

# Create a profile frame for this node
function _flamegraph_frame(io::IO, node::InferenceTimingNode, start_secs, check_precompilable::Bool, excluded_modules, mode; toplevel)
    function func_name(mi::MethodInstance, ::Nothing)
        m = mi.def
        return isa(m, Method) ? string(m.module, '.', m.name) : string(m, '.', "thunk")
    end
    function func_name(mi::MethodInstance, methcounts::AbstractDict{Method})
        str = func_name(mi, nothing)
        m = mi.def
        if isa(m, Method)
            n = get(methcounts, m, nothing)
            if n !== nothing
                str = string(str, " (", n, ')')
            end
        end
        return str
    end
    function func_name(io::IO, mi_info::InferenceFrameInfo, mode)
        if mode === :slots
            show(io, mi_info)
            str = String(take!(io))
            startswith(str, "InferenceFrameInfo for ") && (str = str[length("InferenceFrameInfo for ")+1:end])
            return str
        elseif mode == :spec
            return frame_name(io, mi_info)
        else
            return func_name(MethodInstance(mi_info), mode)
        end
    end

    mistr = Symbol(func_name(io, InferenceTiming(node).mi_info, mode))
    mi = MethodInstance(node)
    m = mi.def
    sf = isa(m, Method) ? StackFrame(mistr, mi.def.file, mi.def.line, mi, false, false, UInt64(0x0)) :
                          StackFrame(mistr, :unknown, 0, mi, false, false, UInt64(0x0))
    if check_precompilable
        mod = isa(m, Method) ? m.module : m
        ispc = isprecompilable(mi; excluded_modules)
        status, check_precompilable = UInt8(!ispc), !ispc
    else
        status = 0x0  # "default" status -- see FlameGraphs.jl
    end
    start = node.start_time - start_secs
    if toplevel
        # Compute a range over the whole profile for the top node.
        range = round(Int, start*1e9) : round(Int, (max_end_time(node) - start_secs)*1e9)
    else
        range = round(Int, start*1e9) : round(Int, (start + inclusive(node))*1e9)
    end
    return FlameGraphs.NodeData(sf, status, range), check_precompilable
end


function frame_name(io::IO, mi_info::InferenceFrameInfo)
    frame_name(io, mi_info.mi::MethodInstance)
end
function frame_name(io::IO, mi::MethodInstance)
    m = mi.def
    isa(m, Module) && return "thunk"
    return frame_name(io, m.name, mi.specTypes)
end
# Special printing for Type Tuples so they're less ugly in the FlameGraph
function frame_name(io::IO, name, @nospecialize(tt::Type{<:Tuple}))
    try
        Base.show_tuple_as_call(io, name, tt)
        v = String(take!(io))
        return v
    catch e
        e isa InterruptException && rethrow()
        @warn "Error displaying frame: $e"
        return name
    end
end

# NOTE: The "root" node doesn't cover the whole profile, because it's only the _complement_
# of the inference times (so it's missing the _overhead_ from the measurement).
# SO we need to manually create a root node that covers the whole thing.
function max_end_time(node::InferenceTimingNode)
    # It's possible that node is already the longest-reaching node.
    t_end = node.start_time + inclusive(node)
    # It's also possible that the last child extends past the end of node. (I think this is
    # possible because of the small unmeasured overhead in computing these measurements.)
    last_node = isempty(node.children) ? node : node.children[end]
    child_end = last_node.start_time + inclusive(last_node)
    # Return the maximum end time to make sure the top node covers the entire graph.
    return max(t_end, child_end)
end
