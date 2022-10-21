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

module SnoopiDeepParallelism

# Mutex ordering: MUTEX > jl_typeinf_lock
const MUTEX = ReentrantLock()

mutable struct Invocation
    # start_idx is mutated when older invocations are deleted and the profile is shifted.
    start_idx::Int
    stop_idx::Int
    start_time::UInt64
end
function Invocation(start_idx)
    # Start at the current time.
    return Invocation(start_idx, 0, time_ns())
end

"""
Global (locked) vector tracking running snoopi calls, and when they started.
- When one finishes, we lock(inference), export results, clear the inference profiles up to
the next oldest snoopi call, then unlock(inference).

Imagine this is an ongoing inference profile, where each letter is another inference profile
result, and we start two profiles, 1 and 2, at the times indicated below:
    ABCDEFGHIJKLMNOPQRSTUVWX
    1> 2>              <1 <2

    - invocations: [(1,A),  (2,D)]
    - 1 ends:
        copy out ABCDEFGHIJKLMNOPQRSTU
        pop (1,A) from invocations
        read oldest invocation: (2,D)
        delete up to D.
        - New profile:
            DEFGHIJKLMNOPQRSTUVWX
            2>                 <2

    - 2 ends:
        copy out DEFGHIJKLMNOPQRSTUVWX
        pop (2,D) from invocations
        no active invocations, so ...
        ... delete up to X (end of this profile).
"""
const invocations = Invocation[]

function _current_profile_length_locked()
    ccall(:jl_typeinf_lock_begin, Cvoid, ())
    try
        inference_root_timing = Core.Compiler.Timings._timings[1]
        children = inference_root_timing.children
        return length(children)
    finally
        ccall(:jl_typeinf_lock_end, Cvoid, ())
    end
end

function _fetch_profile_buffer_locked(start_idx, stop_idx)
    ccall(:jl_typeinf_lock_begin, Cvoid, ())
    try
        inference_root_timing = Core.Compiler.Timings._timings[1]
        children = inference_root_timing.children
        return children[start_idx:stop_idx]
    finally
        ccall(:jl_typeinf_lock_end, Cvoid, ())
    end
end

function start_timing_invocation()
    # Locking respects mutex ordering.
    Base.@lock MUTEX begin
        profile_start_idx = _current_profile_length_locked() + 1
        invocation = Invocation(profile_start_idx)
        push!(invocations, invocation)
        return invocation
    end
end

function stop_timing_invocation!(invocation)
    invocation.stop_idx = _current_profile_length_locked()
end

function finish_timing_invocation_and_clear_profile(invocation)
    # Locking respects mutex ordering.
    Base.@lock MUTEX begin
        # Check if this invocation was the oldest. If so, we'll want to clear the parts of
        # the profile only it was using.
        if invocations[1] !== invocation
            idx = findfirst(==(invocation), invocations)
            @assert idx !== nothing  "invocation wasn't found in invocations: $invocation."
            deleteat!(invocations, idx)
            return
        end

        # Clear this invocation from the invocations vector.
        popfirst!(invocations)

        # Now clear the global inference profile up to the start of the next invocation.
        # If no next invocations, clear them all.
        if isempty(invocations)
            ccall(:jl_typeinf_lock_begin, Cvoid, ())
            try
                Core.Compiler.Timings.reset_timings()
            finally
                ccall(:jl_typeinf_lock_end, Cvoid, ())
            end
            return
        end

        # Else, we stop at the next oldest invocation.
        next_oldest = invocations[1]
        start_idx = next_oldest.start_idx
        to_delete = start_idx - 1
        if to_delete == 0
            return
        end
        # Shift back the indices for all the running invocations
        for running_invocation in invocations
            running_invocation.start_idx -= to_delete
            running_invocation.stop_idx -= to_delete
        end
        # Clear the profile up to the start of the new oldest invocation.
        ccall(:jl_typeinf_lock_begin, Cvoid, ())
        try
            inference_root_timing = Core.Compiler.Timings._timings[1]
            children = inference_root_timing.children
            deleteat!(children, 1:to_delete)
        finally
            ccall(:jl_typeinf_lock_end, Cvoid, ())
        end
    end
end

end  # module

function start_deep_timing()
    invocation = SnoopiDeepParallelism.start_timing_invocation()
    Core.Compiler.__set_measure_typeinf(true)
    return invocation
end
function stop_deep_timing!(invocation)
    Core.Compiler.__set_measure_typeinf(false)
    return SnoopiDeepParallelism.stop_timing_invocation!(invocation)
end

function finish_snoopi_deep(invocation)
    buffer = SnoopiDeepParallelism._fetch_profile_buffer_locked(invocation.start_idx, invocation.stop_idx)

    # Clean up the profile buffer, so that we don't leak memory.
    SnoopiDeepParallelism.finish_timing_invocation_and_clear_profile(invocation)

    root_node = _create_finished_ROOT_Timing(invocation, buffer)
    return InferenceTimingNode(root_node)
end

# The MethodInstance for ROOT(), and default empty values for other fields.
# Copied from julia typeinf
root_inference_frame_info() =
    Core.Compiler.Timings.InferenceFrameInfo(Core.Compiler.Timings.ROOTmi, 0x0, Any[], Any[Core.Const(Core.Compiler.Timings.ROOT)], 1)

function _create_finished_ROOT_Timing(invocation, buffer)
    total_time = time_ns() - invocation.start_time

    # Create a new ROOT() node, specific to this profiling invocation, which wraps the
    # current profile buffer, and contains the total time for the profile.
    return Core.Compiler.Timings.Timing(
        root_inference_frame_info(),
        invocation.start_time,
        0,
        # TODO: This is wrong, this is supposed to be the total exclusive ROOT time.
        #  we should get this off the ROOT() timing when we stop!() the invocation.
        total_time,
        # Use the copied-out section of the profile buffer as the children of ROOT()
        buffer,
    )
end



function _snoopi_deep(cmd::Expr)
    return quote
        invocation = start_deep_timing()
        try
            $(esc(cmd))
        finally
            stop_deep_timing!(invocation)
        end
        # return the timing result:
        finish_snoopi_deep(invocation)
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
precompile(stop_deep_timing!, (SnoopiDeepParallelism.Invocation,))
precompile(finish_snoopi_deep, (SnoopiDeepParallelism.Invocation,))
