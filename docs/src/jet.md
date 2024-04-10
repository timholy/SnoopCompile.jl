# [JET integration](@id JET)

[JET](https://github.com/aviatesk/JET.jl) is a powerful tool for analyzing call graphs.
Some of its functionality overlaps that of SnoopCompile's, that is, JET also provides mechanisms to detect potential errors.
Conversely, JET is a purely static-analysis tool and lacks SnoopCompile's ability to "bridge" across runtime dispatch.
In summary, JET doesn't need Julia to restart to find inference failures, but JET will only find the first inference failure.
SnoopCompile has to run in a fresh session, but finds all inference failures.

For this reason, the combination of the tools provides capabilities that neither package has on its own.
Specifically, one can use SnoopCompile to collect data on the callgraph and JET to perform the error analysis.

The integration between the two packages is bundled into SnoopCompile, specifically [`report_callee`](@ref),
[`report_callees`](@ref), and [`report_caller`](@ref). These take [`InferenceTrigger`](@ref) (see the page on [inference failures](@ref inferrability)) and use them to generate JET reports.

We can demonstrate both the need and use of these tools with a simple extended example.

## JET usage

JET provides a useful report for the following call:

```jldoctest jet; filter=[r"@ reduce.*", r"(in|@)", r"(REPL\[\d+\]|none)"]
julia> using JET

julia> list = Any[1,2,3];

julia> sum(list)
6

julia> @report_call sum(list)
═════ 1 possible error found ═════
┌ @ reducedim.jl:889 Base.#sum#732(Base.:, Base.pairs(Core.NamedTuple()), #self#, a)
│┌ @ reducedim.jl:889 Base._sum(a, dims)
││┌ @ reducedim.jl:893 Base.#_sum#734(Base.pairs(Core.NamedTuple()), #self#, a, _3)
│││┌ @ reducedim.jl:893 Base._sum(Base.identity, a, Base.:)
││││┌ @ reducedim.jl:894 Base.#_sum#735(Base.pairs(Core.NamedTuple()), #self#, f, a, _4)
│││││┌ @ reducedim.jl:894 Base.mapreduce(f, Base.add_sum, a)
││││││┌ @ reducedim.jl:322 Base.#mapreduce#725(Base.:, Base._InitialValue(), #self#, f, op, A)
│││││││┌ @ reducedim.jl:322 Base._mapreduce_dim(f, op, init, A, dims)
││││││││┌ @ reducedim.jl:330 Base._mapreduce(f, op, Base.IndexStyle(A), A)
│││││││││┌ @ reduce.jl:402 Base.mapreduce_empty_iter(f, op, A, Base.IteratorEltype(A))
││││││││││┌ @ reduce.jl:353 Base.reduce_empty_iter(Base.MappingRF(f, op), itr, ItrEltype)
│││││││││││┌ @ reduce.jl:357 Base.reduce_empty(op, Base.eltype(itr))
││││││││││││┌ @ reduce.jl:331 Base.mapreduce_empty(Base.getproperty(op, :f), Base.getproperty(op, :rf), _)
│││││││││││││┌ @ reduce.jl:345 Base.reduce_empty(op, T)
││││││││││││││┌ @ reduce.jl:322 Base.reduce_empty(Base.+, _)
│││││││││││││││┌ @ reduce.jl:313 Base.zero(_)
││││││││││││││││┌ @ missing.jl:106 Base.throw(Base.MethodError(Base.zero, Core.tuple(Base.Any)))
│││││││││││││││││ MethodError: no method matching zero(::Type{Any})
││││││││││││││││└──────────────────
```

The final line reveals that while `sum` happened to work for the specific `list` we provided, it nevertheless has a "gotcha" for the types we supplied: if `list` happens to be empty, `sum` depends on the ability to generate `zero(T)` for the element-type `T` of `list`, but because we constructed `list` to have an element-type of `Any`, there is no such method and `sum(Any[])` throws an error:

```jldoctest
julia> sum(Int[])
0

julia> sum(Any[])
ERROR: MethodError: no method matching zero(::Type{Any})
[...]
```

(This can be circumvented with `sum(Any[]; init=0)`.)

This is the kind of bug that can "lurk" undetected for a long time, and JET excels at exposing them.

## JET limitations

JET is a *static* analyzer, meaning that it works from the argument types provided, and that has an important consequence: if a particular callee can't be inferred, JET can't analyze it. We can illustrate that quite easily:

```jldoctest jet
julia> callsum(listcontainer) = sum(listcontainer[1])
callsum (generic function with 1 method)

julia> lc = Any[list];   # "hide" `list` inside a Vector{Any}

julia> callsum(lc)
6

julia> @report_call callsum(lc)
No errors detected
```

Because we "hid" the type of `list` from inference, JET couldn't tell what specific instance of `sum` was going to be called, so it was unable to detect any errors.

## JET/SnoopCompile integration

The resolution to this problem is to use SnoopCompile to do the "data collection" and JET to do the analysis.
The key reason is that SnoopCompile is a dynamic analyzer, and is capable of bridging across runtime dispatch.
As always, you need to do the data collection in a fresh session where the calls have not previously been inferred.
After restarting Julia, we can do this:

```julia
julia> using SnoopCompile

julia> using JET # this is necessary to enable the integration

julia> list = Any[1,2,3];

julia> lc = Any[list];   # "hide" `list` inside a Vector{Any}

julia> callsum(listcontainer) = sum(listcontainer[1]);

julia> tinf = @snoopi_deep callsum(lc)
InferenceTimingNode: 0.039239/0.046793 on Core.Compiler.Timings.ROOT() with 2 direct children

julia> tinf.children
2-element Vector{SnoopCompileCore.InferenceTimingNode}:
 InferenceTimingNode: 0.000869/0.000869 on callsum(::Vector{Any}) with 0 direct children
 InferenceTimingNode: 0.000196/0.006685 on sum(::Vector{Any}) with 1 direct children

julia> report_callees(inference_triggers(tinf))
1-element Vector{Pair{InferenceTrigger, JET.JETCallResult{JET.JETAnalyzer{JET.BasicPass}, Base.Pairs{Symbol, Union{}, Tuple{}, @NamedTuple{}}}}}:
 Inference triggered to call sum(::Vector{Any}) from callsum (./REPL[5]:1) with specialization callsum(::Vector{Any}) => ═════ 1 possible error found ═════
┌ sum(a::Vector{Any}) @ Base ./reducedim.jl:1010
│┌ sum(a::Vector{Any}; dims::Colon, kw::@Kwargs{}) @ Base ./reducedim.jl:1010
││┌ _sum(a::Vector{Any}, ::Colon) @ Base ./reducedim.jl:1014
│││┌ _sum(a::Vector{Any}, ::Colon; kw::@Kwargs{}) @ Base ./reducedim.jl:1014
││││┌ _sum(f::typeof(identity), a::Vector{Any}, ::Colon) @ Base ./reducedim.jl:1015
│││││┌ _sum(f::typeof(identity), a::Vector{Any}, ::Colon; kw::@Kwargs{}) @ Base ./reducedim.jl:1015
││││││┌ mapreduce(f::typeof(identity), op::typeof(Base.add_sum), A::Vector{Any}) @ Base ./reducedim.jl:357
│││││││┌ mapreduce(f::typeof(identity), op::typeof(Base.add_sum), A::Vector{Any}; dims::Colon, init::Base._InitialValue) @ Base ./reducedim.jl:357
││││││││┌ _mapreduce_dim(f::typeof(identity), op::typeof(Base.add_sum), ::Base._InitialValue, A::Vector{Any}, ::Colon) @ Base ./reducedim.jl:365
│││││││││┌ _mapreduce(f::typeof(identity), op::typeof(Base.add_sum), ::IndexLinear, A::Vector{Any}) @ Base ./reduce.jl:432
││││││││││┌ mapreduce_empty_iter(f::typeof(identity), op::typeof(Base.add_sum), itr::Vector{Any}, ItrEltype::Base.HasEltype) @ Base ./reduce.jl:380
│││││││││││┌ reduce_empty_iter(op::Base.MappingRF{typeof(identity), typeof(Base.add_sum)}, itr::Vector{Any}, ::Base.HasEltype) @ Base ./reduce.jl:384
││││││││││││┌ reduce_empty(op::Base.MappingRF{typeof(identity), typeof(Base.add_sum)}, ::Type{Any}) @ Base ./reduce.jl:361
│││││││││││││┌ mapreduce_empty(::typeof(identity), op::typeof(Base.add_sum), T::Type{Any}) @ Base ./reduce.jl:372
││││││││││││││┌ reduce_empty(::typeof(Base.add_sum), ::Type{Any}) @ Base ./reduce.jl:352
│││││││││││││││┌ reduce_empty(::typeof(+), ::Type{Any}) @ Base ./reduce.jl:343
││││││││││││││││┌ zero(::Type{Any}) @ Base ./missing.jl:106
│││││││││││││││││ MethodError: no method matching zero(::Type{Any}): Base.throw(Base.MethodError(zero, tuple(Base.Any)::Tuple{DataType})::MethodError)
││││││││││││││││└────────────────────
```

Because SnoopCompile collected the runtime-dispatched `sum` call, we can pass it to JET.
`report_callees` filters those calls which generate JET reports, allowing you to focus on potential errors.

!!! note
    JET integration is enabled only if JET.jl has been loaded into your main session.
    This is why there's the `using JET` statement included in the example given.
