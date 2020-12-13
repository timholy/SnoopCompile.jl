import FlameGraphs

using Base.StackTraces: StackFrame
using FlameGraphs.LeftChildRightSiblingTrees: Node, addchild
using Core.Compiler.Timings: Timing

const flamegraph = FlameGraphs.flamegraph  # For re-export

"""
    flatten_times(timing::Core.Compiler.Timings.Timing; tmin_secs = 0.0)

Flatten the execution graph of Timings returned from `@snoopi_deep` into a Vector of pairs,
with the exclusive time for each invocation of type inference, skipping any frames that
took less than `tmin_secs` seconds. Results are sorted by time.

`ROOT` is a dummy element whose time corresponds to the sum of time spent outside inference. It's
the total time of the operation minus the total time for inference. You can run `sum(first.(result[1:end-1]))`
to get the total inference time, and `sum(first.(result))` to get the total time overall.
"""
function flatten_times(timing::Core.Compiler.Timings.Timing; tmin_secs = 0.0)
    out = Pair{Float64,Core.Compiler.Timings.InferenceFrameInfo}[]
    frontier = [timing]
    while !isempty(frontier)
        t = popfirst!(frontier)
        exclusive_time = (t.time / 1e9)
        if exclusive_time >= tmin_secs
            push!(out, exclusive_time => t.mi_info)
        end
        append!(frontier, t.children)
    end
    return sort(out; by=first)
end

"""
    accumulate_by_source(pairs; tmin_secs = 0.0)

Add the inference timings for all `MethodInstance`s of a single `Method` together.
`pairs` is the output of [`flatten_times`](@ref).
Returns a list of `t => method` pairs.

When the accumulated time for a `Method` is large, but each instance is small, it indicates
that it is being inferred for many specializations (which might include specializations with different constants).

# Example

```julia
julia> tinf = @snoopi_deep sort(Float16[1, 2, 3]);

julia> tm = accumulate_by_source(flatten_times(tinf); tmin_secs=0.0005)
6-element Vector{Pair{Float64, Method}}:
 0.000590579 => _copyto_impl!(dest::Array, doffs::Integer, src::Array, soffs::Integer, n::Integer) in Base at array.jl:307
 0.000616788 => partition!(v::AbstractVector{T} where T, lo::Integer, hi::Integer, o::Base.Order.Ordering) in Base.Sort at sort.jl:578
 0.000634394 => sort!(v::AbstractVector{T} where T, lo::Integer, hi::Integer, ::Base.Sort.InsertionSortAlg, o::Base.Order.Ordering) in Base.Sort at sort.jl:527
 0.000720815 => Vector{T}(::UndefInitializer, m::Int64) where T in Core at boot.jl:448
 0.001157551 => getindex(::Type{T}, x, y, z) where T in Base at array.jl:394
 0.046509861 => ROOT() in Core.Compiler.Timings at compiler/typeinfer.jl:75
```

`ROOT` is a dummy element whose time corresponds to the sum of time spent on everything *except* inference.
"""
function accumulate_by_source(pairs::Vector{Pair{Float64,Core.Compiler.Timings.InferenceFrameInfo}}; tmin_secs = 0.0)
    tmp = Dict{Union{Method,MethodInstance},Float64}()
    for (t, info) in pairs
        m = info.mi.def
        if isa(m, Method)
            tmp[m] = get(tmp, m, 0.0) + t
        else
            tmp[info.mi] = t    # module-level thunks are stored verbatim
        end
    end
    return sort([t=>m for (m, t) in tmp if t >= tmin_secs]; by=first)
end

struct InclusiveTiming
    mi_info::Core.Compiler.Timings.InferenceFrameInfo
    inclusive_time::UInt64
    start_time::UInt64
    children::Vector{InclusiveTiming}
end

Base.show(io::IO, t::InclusiveTiming) = print(io, "InclusiveTiming: ", t.inclusive_time/10^9, " for ", t.mi_info.mi, " with ", length(t.children), " direct children")

inclusive_time(t::InclusiveTiming) = t.inclusive_time

"""
    tinc = SnoopCompile.build_inclusive_times(t::Core.Compiler.Timings.Timing)

Calculate times for inference for a node and all its children. `tinc.inclusive_time` records this time for
node `tinc`; `tinc.children` gives you access to the children of this node.
"""
function build_inclusive_times(t::Timing)
    child_times = InclusiveTiming[
        build_inclusive_times(child)
        for child in t.children
    ]
    incl_time = t.time + sum(inclusive_time, child_times; init=UInt64(0))
    return InclusiveTiming(t.mi_info, incl_time, t.start_time, child_times)
end

struct Precompiles
    mi_info::Core.Compiler.Timings.InferenceFrameInfo
    total_time::UInt64
    precompiles::Vector{Tuple{UInt64,MethodInstance}}
end
Precompiles(it::InclusiveTiming) = Precompiles(it.mi_info, it.inclusive_time, Tuple{UInt64,MethodInstance}[])

inclusive_time(t::Precompiles) = t.total_time
precompilable_time(precompiles::Vector{Tuple{UInt64,MethodInstance}}) = sum(first, precompiles; init=zero(UInt64))
precompilable_time(pc::Precompiles) = precompilable_time(pc.precompiles)

function Base.show(io::IO, pc::Precompiles)
    tpc = precompilable_time(pc)
    print(io, "Precompiles: ", pc.total_time/10^9, " for ", pc.mi_info.mi,
              " had ", length(pc.precompiles), " precompilable roots reclaiming ", tpc/10^9,
              " ($(round(Int, 100*tpc/pc.total_time))%)")
end

precompilable_roots(t::Timing) = precompilable_roots(build_inclusive_times(t))
function precompilable_roots(t::InclusiveTiming)
    pcs = [precompilable_roots!(Precompiles(it), it) for it in t.children]
    tpc = precompilable_time.(pcs)
    p = sortperm(tpc)
    return pcs[p]
end

function precompilable_roots!(pc, t::InclusiveTiming)
    mi = t.mi_info.mi
    m = mi.def
    if isa(m, Method)
        mod = m.module
        params = Base.unwrap_unionall(mi.specTypes)::DataType
        can_eval = true
        for p in params.parameters
            if !known_type(mod, p)
                can_eval = false
                break
            end
        end
        if can_eval
            push!(pc.precompiles, (t.inclusive_time, mi))
            return pc
        end
    end
    foreach(t.children) do c
        precompilable_roots!(pc, c)
    end
    return pc
end

function parcel(pcs::Vector{Precompiles})
    tosecs((t, mi)::Tuple{UInt64,MethodInstance}) = (t/10^9, mi)
    pcdict = Dict{Module,Vector{Tuple{UInt64,MethodInstance}}}()
    t_grand_total = sum(inclusive_time, pcs; init=zero(UInt64))
    for pc in pcs
        for (t, mi) in pc.precompiles
            m = mi.def
            mod = isa(m, Method) ? m.module : m
            list = get!(Vector{Tuple{UInt64,MethodInstance}}, pcdict, mod)
            push!(list, (t, mi))
        end
    end
    pclist = [mod => (precompilable_time(list)/10^9, sort!(tosecs.(list); by=first)) for (mod, list) in pcdict]
    sort!(pclist; by = pr -> pr.second[1])
    return t_grand_total/10^9, pclist
end

parcel(t::InclusiveTiming) = parcel(precompilable_roots(t))
parcel(t::Timing) = parcel(build_inclusive_times(t))

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

"""
    flamegraph(t::Core.Compiler.Timings.Timing; tmin_secs=0.0)
    flamegraph(t::SnoopCompile.InclusiveTiming; tmin_secs=0.0)

Convert the call tree of inference timings returned from `@snoopi_deep` into a FlameGraph.
Returns a FlameGraphs.FlameGraph structure that represents the timing trace recorded for
type inference.

Frames that take less than `tmin_secs` seconds of _inclusive time_ will not be included
in the resultant FlameGraph (meaning total time including it and all of its children).
This can be helpful if you have a very big profile, to save on processing time.

# Examples
```julia
julia> timing = @snoopi_deep begin
           @eval sort(rand(100))  # Evaluate some code and profile julia's type inference
       end;

julia> fg = flamegraph(timing)
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:70, 0x00, 0:15355670))

julia> ProfileView.view(fg);  # Display the FlameGraph in a package that supports it

julia> fg = flamegraph(timing; tmin_secs=0.0001)  # Skip very tiny frames
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:70, 0x00, 0:15355670))
```

NOTE: This function must touch every frame in the provided `Timing` to build inclusive
timing information (`InclusiveTiming`). If you have a very large profile, and you plan to
call this function multiple times (say with different values for `tmin_secs`), you can save
some intermediate time by first calling [`SnoopCompile.build_inclusive_times(t)`](@ref), only once,
and then passing in the `InclusiveTiming` object for all subsequent calls.
"""
function FlameGraphs.flamegraph(t::Timing; tmin_secs = 0.0)
    it = build_inclusive_times(t)
    flamegraph(it; tmin_secs=tmin_secs)
end

function FlameGraphs.flamegraph(to::InclusiveTiming; tmin_secs = 0.0)
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
    m = mi.def
    isa(m, Module) && return "thunk"
    return frame_name(m.name, mi.specTypes)
end
# Special printing for Type Tuples so they're less ugly in the FlameGraph
function frame_name(name, @nospecialize(tt::Type{<:Tuple}))
    try
        io = IOBuffer()
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
function max_end_time(t::InclusiveTiming)
    # It's possible that t is already the longest-reaching node.
    t_end = UInt64(t.start_time + t.inclusive_time)
    # It's also possible that the last child extends past the end of t. (I think this is
    # possible because of the small unmeasured overhead in computing these measurements.)
    last_node = length(t.children) > 0 ? t.children[end] : t
    child_end = last_node.start_time + last_node.inclusive_time
    # Return the maximum end time to make sure the top node covers the entire graph.
    return max(t_end, child_end)
end

# Make a flat frame for this Timing
function _flamegraph_frame(to::InclusiveTiming, start_ns; toplevel)
    mi = to.mi_info.mi
    tt = Symbol(frame_name(to.mi_info))
    m = mi.def
    sf = isa(m, Method) ? StackFrame(tt, mi.def.file, mi.def.line, mi, false, false, UInt64(0x0)) :
                          StackFrame(tt, :unknown, 0, mi, false, false, UInt64(0x0))
    status = 0x0  # "default" status -- See FlameGraphs.jl
    start = to.start_time - start_ns
    if toplevel
        # Compute a range over the whole profile for the top node.
        range = Int(start) : Int(max_end_time(to) - start_ns)
    else
        range = Int(start) : Int(start + to.inclusive_time)
    end
    return FlameGraphs.NodeData(sf, status, range)
end
