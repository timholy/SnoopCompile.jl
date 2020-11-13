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
    return sort(out; by=tl->tl[1])
end

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
    incl_time = t.time + sum(inclusive_time, child_times; init=UInt64(0))
    return InclusiveTiming(t.mi_info, incl_time, t.start_time, child_times)
end

@enum FrameDisplayType slottypes method_instance method function_name

"""
    flamegraph(t::Core.Compiler.Timings.Timing;
                tmin_secs = 0.0, display_type = FrameDisplayType.method_instance)
    flamegraph(t::SnoopCompile.InclusiveTiming;
                tmin_secs = 0.0, display_type = FrameDisplayType.method_instance)

Convert the call tree of inference timings returned from `@snoopi_deep` into a FlameGraph.
Returns a FlameGraphs.FlameGraph structure that represents the timing trace recorded for
type inference.

Frames that take less than `tmin_secs` seconds of _inclusive time_ will not be included
in the resultant FlameGraph (meaning total time including it and all of its children).
This can be helpful if you have a very big profile, to save on processing time.

To make it easier to aggregate and understand results, you might try setting a less-precise
display type via e.g. `display_type=FrameDisplayType.method` or
`display_type=FrameDisplayType.function_name`. This can be especially useful for
graph-based displays, such as PProf.jl.

# Keyword Arguments
- `display_type::FrameDisplayType`: How to print the inference frame in the FlameGraph
    - Options: `slottypes, method_instance, method, function_name`

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
function FlameGraphs.flamegraph(t::Timing; tmin_secs = 0.0, display_type = method_instance)
    it = build_inclusive_times(t)
    flamegraph(it; tmin_secs=tmin_secs, display_type=display_type)
end

function FlameGraphs.flamegraph(to::InclusiveTiming; tmin_secs = 0.0, display_type = method_instance)
    tmin_ns = UInt64(round(tmin_secs * 1e9))

    # Compute a "root" frame for the top-level node, to cover the whole profile
    node_data = _flamegraph_frame(to, to.start_time; toplevel=true, display_type=display_type)
    root = Node(node_data)
    return _build_flamegraph!(root, to, to.start_time, tmin_ns, display_type)
end
function _build_flamegraph!(root, to::InclusiveTiming, start_ns, tmin_ns, display_type)
    for child in to.children
        if child.inclusive_time > tmin_ns
            node_data = _flamegraph_frame(child, start_ns; toplevel=false, display_type=display_type)
            node = addchild(root, node_data)
            _build_flamegraph!(node, child, start_ns, tmin_ns, display_type)
        end
    end
    return root
end

function frame_name(mi_info::Core.Compiler.Timings.InferenceFrameInfo; display_type)
    try
        mi = mi_info.mi
        name = mi.def.name
        if display_type == slottypes
            # nargs added in https://github.com/JuliaLang/julia/pull/38416
            st = if hasfield(Core.Compiler.Timings.InferenceFrameInfo, :nargs)
                mi_info.slottypes[1:mi_info.nargs]
            else
                mi_info.slottypes
            end
            frame_name_slottypes(st)
        elseif display_type == function_name
            string(name)
        elseif display_type == method
            string(mi.def)
        elseif display_type == method_instance
            frame_name(mi.def.name, mi.specTypes)
        else
            throw("Unsupported display_type: $display_type")
        end
    catch e
        e isa InterruptException && rethrow()
        @warn "Error displaying frame: $e"
        return "<Error displaying frame>"
    end
end
function frame_name(name, ::Type{TT}) where TT<:Tuple
    try
        io = IOBuffer()
        Base.show_tuple_as_call(io, name, TT)
        v = String(take!(io))
        return v
    catch e
        e isa InterruptException && rethrow()
        @warn "Error displaying frame: $e"
        return name
    end
end
function frame_name_slottypes(slottypes)
    name = slottypes[1].val
    try
        return "$(repr(name))(" *
        join((if t isa Core.Const "$t::$(typeof(t.val))" else "::$t" end
            for t in slottypes[2:end]),
            ", "
        ) *
        ")"
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
function _flamegraph_frame(to::InclusiveTiming, start_ns; toplevel, display_type)
    mi = to.mi_info.mi
    tt = Symbol(frame_name(to.mi_info; display_type=display_type))
    sf = StackFrame(tt, mi.def.file, mi.def.line, mi, false, false, UInt64(0x0))
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
