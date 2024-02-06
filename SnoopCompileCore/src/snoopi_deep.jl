const have_clear_and_fetch_timings = isdefined(Core.Compiler, :Timings) && isdefined(Core.Compiler.Timings, :clear_and_fetch_timings)

using Core.Compiler.Timings: ROOT, ROOTmi, InferenceFrameInfo, Timing

struct InferenceTiming
    mi_info::Core.Compiler.Timings.InferenceFrameInfo
    inclusive_time::Float64
    exclusive_time::Float64
end
"""
    inclusive(frame)

Return the time spent inferring `frame` and its callees.
"""
inclusive(it::InferenceTiming) = it.inclusive_time
"""
    exclusive(frame)

Return the time spent inferring `frame`, not including the time needed for any of its callees.
"""
exclusive(it::InferenceTiming) = it.exclusive_time

struct InferenceTimingNode
    mi_timing::InferenceTiming
    start_time::Float64
    children::Vector{InferenceTimingNode}
    bt
    parent::InferenceTimingNode

    # Root constructor
    InferenceTimingNode(mi_timing::InferenceTiming, start_time, @nospecialize(bt)) =
        new(mi_timing, start_time, InferenceTimingNode[], bt)
    # Child constructor
    function InferenceTimingNode(mi_timing::InferenceTiming, start_time, @nospecialize(bt), parent::InferenceTimingNode)
        child = new(mi_timing, start_time, InferenceTimingNode[], bt, parent)
        push!(parent.children, child)
        return child
    end
end
inclusive(node::InferenceTimingNode) = inclusive(node.mi_timing)
exclusive(node::InferenceTimingNode) = exclusive(node.mi_timing)
InferenceTiming(node::InferenceTimingNode) = node.mi_timing

function InferenceTimingNode(t::Core.Compiler.Timings.Timing)
    ttree = timingtree(t)
    it, start_time, ttree_children = ttree::Tuple{InferenceTiming, Float64, Vector{Any}}
    root = InferenceTimingNode(it, start_time, t.bt)
    addchildren!(root, t, ttree_children)
    return root
end

# Compute inclusive times and store as a temporary tree.
# To allow InferenceTimingNode to be both bidirectional and immutable, we need to create parent node before the child nodes.
# However, each node stores its inclusive time, which can only be computed efficiently from the leaves up (children before parents).
# This performs the inclusive-time computation, storing the result as a "temporary tree" that can be used during
# InferenceTimingNode creation (see `addchildren!`).
function timingtree(t::Core.Compiler.Timings.Timing)
    time, start_time = t.time/10^9, t.start_time/10^9
    incl_time = time
    tchildren = []
    for child in t.children
        tchild = timingtree(child)
        push!(tchildren, tchild)
        incl_time += inclusive(tchild[1])
    end
    return (InferenceTiming(t.mi_info, incl_time, time), start_time, tchildren)
end

function addchildren!(parent::InferenceTimingNode, t::Core.Compiler.Timings.Timing, ttrees)
    for (child, ttree) in zip(t.children, ttrees)
        it, start_time, ttree_children = ttree::Tuple{InferenceTiming, Float64, Vector{Any}}
        node = InferenceTimingNode(it, start_time, child.bt, parent)
        addchildren!(node, child, ttree_children)
    end
end

if have_clear_and_fetch_timings
    function start_deep_timing()
        Core.Compiler.__set_measure_typeinf(true)
    end
    function stop_deep_timing()
        Core.Compiler.__set_measure_typeinf(false)
    end
    function finish_snoopi_deep()
        # Construct a dummy Timing for ROOT(), for backwards compatibility with the old API.
        root = Timing(
            InferenceFrameInfo(ROOTmi, 0x0, Any[], Any[Core.Const(ROOT)], 1),
            0x0)
        root.children = Core.Compiler.Timings.clear_and_fetch_timings()

        return InferenceTimingNode(root)
    end
else
    function start_deep_timing()
        Core.Compiler.Timings.reset_timings()
        Core.Compiler.__set_measure_typeinf(true)
    end
    function stop_deep_timing()
        Core.Compiler.__set_measure_typeinf(false)
        Core.Compiler.Timings.close_current_timer()
    end
    function finish_snoopi_deep()
        return InferenceTimingNode(Core.Compiler.Timings._timings[1])
    end
end

function _snoopi_deep(cmd::Expr)
    return quote
        start_deep_timing()
        try
            $(esc(cmd))
        finally
            stop_deep_timing()
        end
        finish_snoopi_deep()
    end
end

"""
    tinf = @snoopi_deep commands

Produce a profile of julia's type inference, recording the amount of time spent inferring
every `MethodInstance` processed while executing `commands`. Each fresh entrance to
type inference (whether executed directly in `commands` or because a call was made
by runtime-dispatch) also collects a backtrace so the caller can be identified.

`tinf` is a tree, each node containing data on a particular inference "frame" (the method,
argument-type specializations, parameters, and even any constant-propagated values).
Each reports the [`exclusive`](@ref)/[`inclusive`](@ref) times, where the exclusive
time corresponds to the time spent inferring this frame in and of itself, whereas
the inclusive time includes the time needed to infer all the callees of this frame.

The top-level node in this profile tree is `ROOT`. Uniquely, its exclusive time
corresponds to the time spent _not_ in julia's type inference (codegen, llvm_opt, runtime, etc).

There are many different ways of inspecting and using the data stored in `tinf`.
The simplest is to load the `AbstracTrees` package and display the tree with
`AbstractTrees.print_tree(tinf)`.
See also:  `flamegraph`, `flatten`, `inference_triggers`, `SnoopCompile.parcel`,
`runtime_inferencetime`.

# Example
```jldoctest; setup=:(using SnoopCompile), filter=r"([0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?/[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?|\\d direct)"
julia> tinf = @snoopi_deep begin
           sort(rand(100))  # Evaluate some code and profile julia's type inference
       end
InferenceTimingNode: 0.110018224/0.131464476 on Core.Compiler.Timings.ROOT() with 2 direct children
```

"""
macro snoopi_deep(cmd)
    return _snoopi_deep(cmd)
end

# These are okay to come at the top-level because we're only measuring inference, and
# inference results will be cached in a `.ji` file.
precompile(start_deep_timing, ())
precompile(stop_deep_timing, ())
precompile(finish_snoopi_deep, ())
