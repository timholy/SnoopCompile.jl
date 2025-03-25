export @snoop_inference

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

const snoop_inference_lock = ReentrantLock()
const newly_inferred = Core.CodeInstance[]

function start_tracking()
    islocked(snoop_inference_lock) && error("already tracking inference (cannot nest `@snoop_inference` blocks)")
    lock(snoop_inference_lock)
    empty!(newly_inferred)
    ccall(:jl_set_newly_inferred, Cvoid, (Any,), newly_inferred)
    return nothing
end

function stop_tracking()
    @assert islocked(snoop_inference_lock)
    ccall(:jl_set_newly_inferred, Cvoid, (Any,), nothing)
    unlock(snoop_inference_lock)
    return nothing
end

"""
    tinf = @snoop_inference commands;

Produce a profile of julia's type inference, recording the amount of time spent
inferring every `MethodInstance` processed while executing `commands`. Each
fresh entrance to type inference (whether executed directly in `commands` or
because a call was made by runtime-dispatch) also collects a backtrace so the
caller can be identified.

`tinf` is a tree, each node containing data on a particular inference "frame"
(the method, argument-type specializations, parameters, and even any
constant-propagated values). Each reports the
[`exclusive`](@ref)/[`inclusive`](@ref) times, where the exclusive time
corresponds to the time spent inferring this frame in and of itself, whereas the
inclusive time includes the time needed to infer all the callees of this frame.

The top-level node in this profile tree is `ROOT`. Uniquely, its exclusive time
corresponds to the time spent _not_ in julia's type inference (codegen,
llvm_opt, runtime, etc).

Working with `tinf` effectively requires loading `SnoopCompile`.

!!! warning
    Note the semicolon `;` at the end of the `@snoop_inference` macro call.
    Because `SnoopCompileCore` is not permitted to invalidate any code, it cannot define
    the `Base.show` methods that pretty-print `tinf`. Defer inspection of `tinf`
    until `SnoopCompile` has been loaded.

# Example

```jldoctest; setup=:(using SnoopCompileCore), filter=r"([0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?/[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?|\\d direct)"
julia> tinf = @snoop_inference begin
           sort(rand(100))  # Evaluate some code and profile julia's type inference
       end;
```
"""
macro snoop_inference(cmd)
    return esc(quote
        $(SnoopCompileCore.start_tracking)()
        try
            $cmd
        finally
            $(SnoopCompileCore.stop_tracking)()
        end
        ($(Base.copy))($(SnoopCompileCore.newly_inferred))
    end)
end

precompile(start_tracking, ())
precompile(stop_tracking, ())
