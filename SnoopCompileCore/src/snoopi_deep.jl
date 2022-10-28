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

"""
    flatten(tinf; tmin = 0.0, sortby=exclusive)

Flatten the execution graph of `InferenceTimingNode`s returned from `@snoopi_deep` into a Vector of `InferenceTiming`
frames, each encoding the time needed for inference of a single `MethodInstance`.
By default, results are sorted by `exclusive` time (the time for inferring the `MethodInstance` itself, not including
any inference of its callees); other options are `sortedby=inclusive` which includes the time needed for the callees,
or `nothing` to obtain them in the order they were inferred (depth-first order).

# Example

We'll use [`SnoopCompile.flatten_demo`](@ref), which runs `@snoopi_deep` on a workload designed to yield reproducible results:

```jldoctest flatten; setup=:(using SnoopCompile), filter=r"([0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?/[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?|WARNING: replacing module FlattenDemo\\.\\n)"
julia> tinf = SnoopCompile.flatten_demo()
InferenceTimingNode: 0.002148974/0.002767166 on Core.Compiler.Timings.ROOT() with 1 direct children

julia> using AbstractTrees; print_tree(tinf)
InferenceTimingNode: 0.00242354/0.00303526 on Core.Compiler.Timings.ROOT() with 1 direct children
└─ InferenceTimingNode: 0.000150891/0.000611721 on SnoopCompile.FlattenDemo.packintype(::$Int) with 2 direct children
   ├─ InferenceTimingNode: 0.000105318/0.000105318 on SnoopCompile.FlattenDemo.MyType{$Int}(::$Int) with 0 direct children
   └─ InferenceTimingNode: 9.43e-5/0.000355512 on SnoopCompile.FlattenDemo.dostuff(::SnoopCompile.FlattenDemo.MyType{$Int}) with 2 direct children
      ├─ InferenceTimingNode: 6.6458e-5/0.000124716 on SnoopCompile.FlattenDemo.extract(::SnoopCompile.FlattenDemo.MyType{$Int}) with 2 direct children
      │  ├─ InferenceTimingNode: 3.401e-5/3.401e-5 on getproperty(::SnoopCompile.FlattenDemo.MyType{$Int}, ::Symbol) with 0 direct children
      │  └─ InferenceTimingNode: 2.4248e-5/2.4248e-5 on getproperty(::SnoopCompile.FlattenDemo.MyType{$Int}, x::Symbol) with 0 direct children
      └─ InferenceTimingNode: 0.000136496/0.000136496 on SnoopCompile.FlattenDemo.domath(::$Int) with 0 direct children
```

Note the printing of `getproperty(::SnoopCompile.FlattenDemo.MyType{$Int}, x::Symbol)`: it shows the specific Symbol, here `:x`,
that `getproperty` was inferred with. This reflects constant-propagation in inference.

Then:
```jldoctest flatten; setup=:(using SnoopCompile), filter=[r"[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?/[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?", r"WARNING: replacing module FlattenDemo.*"]
julia> flatten(tinf; sortby=nothing)
8-element Vector{SnoopCompileCore.InferenceTiming}:
 InferenceTiming: 0.002423543/0.0030352639999999998 on Core.Compiler.Timings.ROOT()
 InferenceTiming: 0.000150891/0.0006117210000000001 on SnoopCompile.FlattenDemo.packintype(::$Int)
 InferenceTiming: 0.000105318/0.000105318 on SnoopCompile.FlattenDemo.MyType{$Int}(::$Int)
 InferenceTiming: 9.43e-5/0.00035551200000000005 on SnoopCompile.FlattenDemo.dostuff(::SnoopCompile.FlattenDemo.MyType{$Int})
 InferenceTiming: 6.6458e-5/0.000124716 on SnoopCompile.FlattenDemo.extract(::SnoopCompile.FlattenDemo.MyType{$Int})
 InferenceTiming: 3.401e-5/3.401e-5 on getproperty(::SnoopCompile.FlattenDemo.MyType{$Int}, ::Symbol)
 InferenceTiming: 2.4248e-5/2.4248e-5 on getproperty(::SnoopCompile.FlattenDemo.MyType{$Int}, x::Symbol)
 InferenceTiming: 0.000136496/0.000136496 on SnoopCompile.FlattenDemo.domath(::$Int)
```

```
julia> flatten(tinf; tmin=1e-4)                        # sorts by exclusive time (the time before the '/')
4-element Vector{SnoopCompileCore.InferenceTiming}:
 InferenceTiming: 0.000105318/0.000105318 on SnoopCompile.FlattenDemo.MyType{$Int}(::$Int)
 InferenceTiming: 0.000136496/0.000136496 on SnoopCompile.FlattenDemo.domath(::$Int)
 InferenceTiming: 0.000150891/0.0006117210000000001 on SnoopCompile.FlattenDemo.packintype(::$Int)
 InferenceTiming: 0.002423543/0.0030352639999999998 on Core.Compiler.Timings.ROOT()

julia> flatten(tinf; sortby=inclusive, tmin=1e-4)      # sorts by inclusive time (the time after the '/')
6-element Vector{SnoopCompileCore.InferenceTiming}:
 InferenceTiming: 0.000105318/0.000105318 on SnoopCompile.FlattenDemo.MyType{$Int}(::$Int)
 InferenceTiming: 6.6458e-5/0.000124716 on SnoopCompile.FlattenDemo.extract(::SnoopCompile.FlattenDemo.MyType{$Int})
 InferenceTiming: 0.000136496/0.000136496 on SnoopCompile.FlattenDemo.domath(::$Int)
 InferenceTiming: 9.43e-5/0.00035551200000000005 on SnoopCompile.FlattenDemo.dostuff(::SnoopCompile.FlattenDemo.MyType{$Int})
 InferenceTiming: 0.000150891/0.0006117210000000001 on SnoopCompile.FlattenDemo.packintype(::$Int)
 InferenceTiming: 0.002423543/0.0030352639999999998 on Core.Compiler.Timings.ROOT()
```

As you can see, `sortby` affects not just the order but also the selection of frames; with exclusive times, `dostuff` did
not on its own rise above threshold, but it does when using inclusive times.

See also: [`accumulate_by_source`](@ref).
"""
function flatten(tinf::InferenceTimingNode; tmin = 0.0, sortby::Union{typeof(exclusive),typeof(inclusive),Nothing}=exclusive)
    out = InferenceTiming[]
    flatten!(sortby === nothing ? exclusive : sortby, out, tinf, tmin)
    return sortby===nothing ? out : sort(out; by=sortby)
end

function flatten!(gettime::Union{typeof(exclusive),typeof(inclusive)}, out, node, tmin)
    time = gettime(node)
    if time >= tmin
        push!(out, node.mi_timing)
    end
    for child in node.children
        flatten!(gettime, out, child, tmin)
    end
    return out
end

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
