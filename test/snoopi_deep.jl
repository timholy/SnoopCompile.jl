using SnoopCompile
using SnoopCompile.SnoopCompileCore
using SnoopCompile.FlameGraphs
using Test
using InteractiveUtils
using Random
using Profile
using MethodAnalysis
using Core: MethodInstance
using Pkg
# using PyPlot: PyPlot, plt    # uncomment to test visualizations

using SnoopCompile.FlameGraphs.AbstractTrees  # For FlameGraphs tests

# Constant-prop works differently on different Julia versions.
# This utility lets you strip frames that const-prop a number.
hasconstpropnumber(f::SnoopCompileCore.InferenceTiming) = hasconstpropnumber(f.mi_info)
hasconstpropnumber(mi_info::Core.Compiler.Timings.InferenceFrameInfo) = any(t -> isa(t, Core.Const) && isa(t.val, Number), mi_info.slottypes)

@testset "@snoopi_deep" begin
    # WARMUP (to compile all the small, reachable methods)
    M = Module()
    @eval M begin # Example with some functions that include type instability
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end
    M.g(2)  # Warmup all deeply reachable functions
    M.g(true)

    # Redefine the module, so the snoop will only show these functions:
    M = Module()
    @eval M begin # Example with some functions that include type instability
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end

    tinf = @snoopi_deep begin
        M.g(2)
        M.g(true)
    end
    @test SnoopCompile.isROOT(Core.MethodInstance(tinf))
    @test SnoopCompile.isROOT(Method(tinf))
    child = tinf.children[1]
    @test convert(SnoopCompile.InferenceTiming, child).inclusive_time > 0
    @test SnoopCompile.getroot(child.children[1]) == child
    @test SnoopCompile.getroot(child.children[1].children[1]) == child
    @test isempty(staleinstances(tinf))
    frames = filter(!hasconstpropnumber, flatten(tinf))
    @test length(frames) == 7  # ROOT, g(::Int), g(::Bool), h(...), i(::Integer), i(::Int), i(::Bool)
    @test issorted(frames; by=exclusive)
    names = [Method(frame).name for frame in frames]
    @test sort(names) == [:ROOT, :g, :g, :h, :i, :i, :i]
    mg = which(M.g, (Int,))
    tinfsg = collect_for(mg, tinf)
    @test length(tinfsg) == 2
    @test all(node -> Method(node) == mg, tinfsg)
    mig = MethodInstance(first(tinfsg))
    tinfsg1 = collect_for(mig, tinf)
    @test length(tinfsg1) == 1
    @test MethodInstance(tinfsg1[1]) == mig
    @test all(node -> Method(node) == mg, tinfsg)

    longest_frame_time = exclusive(frames[end])
    @test length(flatten(tinf, tmin=longest_frame_time)) == 1

    frames_unsorted = filter(!hasconstpropnumber, flatten(tinf; sortby=nothing))
    ifi = frames_unsorted[1].mi_info
    @test SnoopCompile.isROOT(Core.MethodInstance(ifi))
    @test SnoopCompile.isROOT(Method(ifi))
    names = [Method(frame).name for frame in frames_unsorted]
    argtypes = [MethodInstance(frame).specTypes.parameters[2] for frame in frames_unsorted[2:end]]
    @test names == [:ROOT, :g, :h,           :i,      :i,  :g,   :i]
    @test argtypes == [    Int, Vector{Any}, Integer, Int, Bool, Bool]

    timesm = accumulate_by_source(frames)
    @test length(timesm) == 4
    names = [m.name for (time, m) in timesm]
    @test sort(names) == [:ROOT, :g, :h, :i]
    longest_method_time = timesm[end][1]
    @test length(accumulate_by_source(frames; tmin=longest_method_time)) == 1

    @test SnoopCompile.isROOT(Core.MethodInstance(tinf))
    @test SnoopCompile.isROOT(Method(tinf))
    iframes = flatten(tinf; sortby=inclusive)
    @test issorted(iframes; by=inclusive)

    t = map(inclusive, frames_unsorted)
    @test t[2] >= t[3] >= t[4]
    ifi = frames_unsorted[2].mi_info
    @test Core.MethodInstance(ifi).def == Method(ifi) == which(M.g, (Int,))
    names = [Method(frame).name for frame in frames_unsorted]
    argtypes = [MethodInstance(frame).specTypes.parameters[2] for frame in frames_unsorted[2:end]]
    @test names == [:ROOT, :g, :h,           :i,      :i,  :g,   :i]
    @test argtypes == [    Int, Vector{Any}, Integer, Int, Bool, Bool]

    # Also check module-level thunks
    @eval module M # Example with some functions that include type instability
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end
    tinfmod = @snoopi_deep begin
        @eval @testset "Outer" begin
            @testset "Inner" begin
                for i = 1:2 M.g(2) end
            end
        end
    end
    frames = flatten(tinfmod)
    timesm = accumulate_by_source(frames)
    timesmod = filter(pr -> isa(pr[2], Core.MethodInstance), timesm)
    @test length(timesmod) == 1
end

# For the higher-order function attribution test, we need to prevent `f2`
# from being passed via closure, so we define these globally.
fdouble(x) = 2x

@testset "inference_triggers" begin
    myplus(x, y) = x + y    # freshly redefined even if tests are re-run
    function f(x)
        x < 0.25 ? 1 :
        x < 0.5  ? 1.0 :
        x < 0.75 ? 0x01 : Float16(1)
    end
    g(c) = myplus(f(c[1]), f(c[2]))
    tinf = @snoopi_deep g([0.7, 0.8])
    @test isempty(staleinstances(tinf))
    itrigs = inference_triggers(tinf; exclude_toplevel=false)
    @test length(itrigs) == 2
    @test suggest(itrigs[1]).categories == [SnoopCompile.FromTestDirect]
    s = suggest(itrigs[2])
    @test SnoopCompile.FromTestCallee ∈ s.categories
    @test SnoopCompile.UnspecCall ∈ s.categories
    @test occursin("myplus", string(MethodInstance(itrigs[2].node).def.name))
    itrigs = inference_triggers(tinf)
    itrig = only(itrigs)
    @test filtermod(@__MODULE__, itrigs) == [itrig]
    @test isempty(filtermod(Base, itrigs))
    io = IOBuffer()
    show(io, itrig)
    str = String(take!(io))
    @test occursin(r".*myplus.*\(::UInt8, ::Float16\)", str)
    @test occursin("from g", str)
    @test occursin(r"with specialization .*::Vector\{Float64\}", str)
    mis = callerinstance.(itrigs)
    @test only(mis).def == which(g, (Any,))
    @test callingframe(itrig).callerframes[1].func === :eval
    @test_throws ArgumentError("it seems you've supplied a child node, but backtraces are collected only at the entrance to inference") inference_triggers(tinf.children[1])
    @test stacktrace(itrig) isa Vector{StackTraces.StackFrame}
    itrig0 = itrig
    counter = 0
    while !isempty(itrig.callerframes) && counter < 1000  # defensively prevent infinite loop
        itrig = callingframe(itrig)
        counter += 1
    end
    @test counter < 1000
    show(io, itrig)
    str = String(take!(io))
    @test occursin("called from toplevel", str)
    @test itrig != itrig0
    @test InferenceTrigger(itrig) == itrig0

    # Tree generation
    itree = trigger_tree(itrigs)
    @test length(itree.children) == 1
    @test isempty(itree.children[1].children)
    print_tree(io, itree)
    @test occursin(r"myplus.*UInt8.*Float16", String(take!(io)))

    # Where the caller is inlined into something else
    callee(x) = 2x
    @inline caller(c) = callee(c[1])
    callercaller(cc) = caller(cc[1])
    callercaller([Any[1]])
    cc = [Any[0x01]]
    tinf = @snoopi_deep callercaller(cc)
    @test isempty(staleinstances(tinf))
    itrigs = inference_triggers(tinf)
    itrig = only(itrigs)
    show(io, itrig)
    str = String(take!(io))
    @test occursin(r"to call .*callee.*\(::UInt8\)", str)
    @test occursin("from caller", str)
    @test occursin(r"inlined into .*callercaller.*\(::Vector{Vector{Any}}\)", str)
    s = suggest(itrig)
    @test !isignorable(s)
    print(io, s)
    @test occursin(r"snoopi_deep\.jl:\d+: non-inferrable or unspecialized call.*::UInt8", String(take!(io)))

    mysqrt(x) = sqrt(x)
    c = Any[1, 1.0, 0x01, Float16(1)]
    tinf = @snoopi_deep map(mysqrt, c)
    @test isempty(staleinstances(tinf))
    itrigs = inference_triggers(tinf)
    itree = trigger_tree(itrigs)
    io = IOBuffer()
    print_tree(io, itree)
    @test occursin(r"mysqrt.*Float64", String(take!(io)))
    print(io, itree)
    @test String(take!(io)) == "TriggerNode for root with 2 direct children"
    @test length(flatten(itree)) > length(c)
    length(suggest(itree).children) == 2
    loctrigs = accumulate_by_source(itrigs)
    show(io, loctrigs)
    @test any(str->occursin("4 callees from 2 callers", str), split(String(take!(io)), '\n'))
    @test filtermod(Base, loctrigs) == loctrigs
    @test isempty(filtermod(@__MODULE__, loctrigs))
    # This actually tests the suggest framework a bit, but...
    for loctrig in loctrigs
        summary(io, loctrig)
    end
    str = String(take!(io))
    @test occursin("1 callees from 1 callers, consider improving inference", str)
    @test occursin("4 callees from 2 callers, consider despecializing the callee", str)
    @test occursin("non-inferrable or unspecialized call", str)
    @test occursin("partial type call", str)
    mtrigs = accumulate_by_source(Method, itrigs)
    for mtrig in mtrigs
        show(io, mtrig)
    end
    str = String(take!(io))
    @test occursin(r"map\(f, A::AbstractArray\) (in|@) Base", str)
    @test occursin("2 callees from 1 caller", str)
    for mtrig in mtrigs
        summary(io, mtrig)
    end
    str = String(take!(io))
    @test occursin(r"map.*had 1 specialization", str)
    @test occursin(r"calling Base\.Generator", str)
    @test occursin("calling mysqrt (3 instances)", str)
    modtrigs = SnoopCompile.parcel(mtrigs)
    @test only(modtrigs).first === Base
    @test filtermod(Base, mtrigs) == mtrigs
    @test isempty(filtermod(@__MODULE__, mtrigs))

    # Multiple callees on the same line
    fline(x) = 2*x[]
    gline(x) = x[]
    fg(x) = fline(gline(x[]))
    cc = Ref{Any}(Ref{Base.RefValue}(Ref(3)))
    tinf = @snoopi_deep fg(cc)
    itrigs = inference_triggers(tinf)
    loctrigs = accumulate_by_source(itrigs)
    @test length(loctrigs) == 2
    loctrigs[1].tag == loctrigs[2].tag

    # Higher order function attribution
    @noinline function mymap!(f, dst, src)
        for i in eachindex(dst, src)
            dst[i] = f(src[i])
        end
        return dst
    end
    @noinline mymap(f::F, src) where F = mymap!(f, Vector{Any}(undef, length(src)), src)
    callmymap(x) = mymap(fdouble, x)
    callmymap(Any[1, 2])  # compile all for one set of types
    x = Any[1.0, 2.0]   # fdouble not yet inferred for Float64
    tinf = @snoopi_deep callmymap(x)
    @test isempty(staleinstances(tinf))
    itrigs = inference_triggers(tinf)
    itrig = only(itrigs)
    @test occursin(r"with specialization .*mymap!.*\(::.*fdouble.*, ::Vector{Any}, ::Vector{Any}\)", string(itrig))
    @test occursin(r"with specialization .*mymap.*\(::.*fdouble.*, ::Vector{Any}\)", string(callingframe(itrig)))
    @test occursin(r"with specialization .*callmymap.*\(::Vector{Any}\)", string(skiphigherorder(itrig)))
    # Ensure we don't skip non-higher order calls
    callfdouble(c) = fdouble(c[1])
    callfdouble(Any[1])
    c = Any[Float16(1)]
    tinf = @snoopi_deep callfdouble(c)
    @test isempty(staleinstances(tinf))
    itrigs = inference_triggers(tinf)
    itrig = only(itrigs)
    @test skiphigherorder(itrig) == itrig

    # With a closure
    M = Module()
    @eval M begin
        function f(c, name)
            stringx(x) = string(x) * name
            stringx(x::Int) = string(x) * name
            stringx(x::Float64) = string(x) * name
            stringx(x::Bool) = string(x) * name

            n = 0
            for x in c
                n += length(stringx(x))
            end
            return n
        end
    end
    c = Any["hey", 7]
    tinf = @snoopi_deep M.f(c, " there")
    itrigs = inference_triggers(tinf)
    @test length(itrigs) > 1
    mtrigs = accumulate_by_source(Method, itrigs)
    summary(io, only(mtrigs))
    str = String(take!(io))
    @test occursin(r"closure.*stringx.*\{String\} at", str)
end

@testset "suggest" begin
    categories(tinf) = suggest(only(inference_triggers(tinf))).categories

    io = IOBuffer()

    # UnspecCall and relation to Test
    M = Module()
    @eval M begin
        callee(x) = 2x
        caller(c) = callee(c[1])
    end
    tinf = @snoopi_deep M.caller(Any[1])
    itrigs = inference_triggers(tinf; exclude_toplevel=false)
    @test length(itrigs) == 2
    s = suggest(itrigs[1])
    @test s.categories == [SnoopCompile.FromTestDirect]
    show(io, s)
    @test occursin(r"called by Test.*ignore", String(take!(io)))
    s = suggest(itrigs[2])
    @test s.categories == [SnoopCompile.FromTestCallee, SnoopCompile.UnspecCall]
    show(io, s)
    @test occursin(r"non-inferrable or unspecialized call.*annotate caller\(c::Vector\{Any\}\) at snoopi_deep.*callee\(::Int", String(take!(io)))

    # Same test, but check the test harness & inlineable detection
    M = Module()
    @eval M begin
        callee(x) = 2x
        @inline caller(c) = callee(c[1])
    end
    cats = categories(@snoopi_deep M.caller(Any[1]))
    @test cats == [SnoopCompile.FromTestCallee, SnoopCompile.CallerInlineable, SnoopCompile.UnspecCall]
    SnoopCompile.show_suggest(io, cats, nothing, nothing)
    @test occursin("non-inferrable or unspecialized call", String(take!(io)))

    # UnspecType
    if Base.VERSION < v"1.9.0-DEV"   # on 1.9 there is no trigger assocated with the partial type call
        M = Module()
        @eval M begin
            struct Container{L,T} x::T end
            Container(x::T) where {T} = Container{length(x),T}(x)
        end
        cats = categories(@snoopi_deep M.Container([1,2,3]))
        @test cats == [SnoopCompile.FromTestCallee, SnoopCompile.UnspecType]
        SnoopCompile.show_suggest(io, cats, nothing, nothing)
        @test occursin("partial type call", String(take!(io)))
    end
    M = Module()
    @eval M begin
        struct Typ end
        struct Container{N,T} x::T end
        Container{N}(x::T) where {N,T} = Container{N,T}(x)
        typeconstruct(c) = Container{3}(c[])
    end
    c = Ref{Any}(M.Typ())
    cats = categories(@snoopi_deep M.typeconstruct(c))
    @test cats == [SnoopCompile.FromTestCallee, SnoopCompile.UnspecType]
    SnoopCompile.show_suggest(io, cats, nothing, nothing)
    # println(String(take!(io)))
    @test occursin("partial type call", String(take!(io)))

    # Invoke
    M = Module()
    @eval M begin
        @noinline callf(@nospecialize(f::Function), x) = f(x)
        g(x) = callf(sqrt, x)
    end
    tinf = @snoopi_deep M.g(3)
    itrigs = inference_triggers(tinf)
    if !isempty(itrigs)
        cats = categories(tinf)
        @test cats == [SnoopCompile.FromTestCallee, SnoopCompile.CallerInlineable, SnoopCompile.Invoke]
        SnoopCompile.show_suggest(io, cats, nothing, nothing)
        @test occursin(r"invoked callee.*may fail to precompile", String(take!(io)))
    else
        @warn "Skipped Invoke test due to improvements in inference"
    end

    # FromInvokeLatest
    M = Module()
    @eval M begin
        f(::Int) = 1
        g(x) = Base.invokelatest(f, x)
    end
    cats = categories(@snoopi_deep M.g(3))
    @test SnoopCompile.FromInvokeLatest ∈ cats
    @test isignorable(cats[1])

    # CalleeVariable
    mysin(x) = 1
    mycos(x) = 2
    docall(ref, x) = ref[](x)
    function callvar(x)
        fref = Ref{Any}(rand() < 0.5 ? mysin : mycos)
        return docall(fref, x)
    end
    cats = categories(@snoopi_deep callvar(0.2))
    @test cats == [SnoopCompile.CalleeVariable]
    SnoopCompile.show_suggest(io, cats, nothing, nothing)
    @test occursin(r"variable callee.*avoid assigning function to variable", String(take!(io)))
    # CalleeVariable as an Argument
    M = Module()
    @eval M begin
        mysin(x) = 1
        mycos(x) = 2
        mytan(x) = 3
        mycsc(x) = 4
        getfunc(::Int) = mysin
        getfunc(::Float64) = mycos
        getfunc(::Char) = mytan
        getfunc(::String) = mycsc
        docall(@nospecialize(f), x) = f(x)
        function callvar(ref, f=nothing)
            x = ref[]
            if f === nothing
                f = getfunc(x)
            end
            return docall(f, x)
        end
    end
    tinf = @snoopi_deep M.callvar(Ref{Any}(0.2))
    cats = suggest(inference_triggers(tinf)[end]).categories
    @test cats == [SnoopCompile.CalleeVariable]
    # CalleeVariable & varargs
    M = Module()
    @eval M begin
        f1va(a...) = 1
        f2va(a...) = 2
        docallva(ref, x) = ref[](x...)
        function callsomething(args)
            fref = Ref{Any}(rand() < 0.5 ? f1va : f2va)
            docallva(fref, args)
        end
    end
    cats = categories(@snoopi_deep M.callsomething(Any['a', 2]))
    @test cats == [SnoopCompile.FromTestCallee, SnoopCompile.CallerInlineable, SnoopCompile.CalleeVariable]
    M = Module()
    @eval M begin
        f1va(a...) = 1
        f2va(a...) = 2
        @noinline docallva(ref, x) = ref[](x...)
        function callsomething(args)
            fref = Ref{Any}(rand() < 0.5 ? f1va : f2va)
            docallva(fref, args)
        end
    end
    cats = categories(@snoopi_deep M.callsomething(Any['a', 2]))
    @test cats == [SnoopCompile.CalleeVariable]

    # CallerVararg
    M = Module()
    @eval M begin
        f1(x) = 2x
        c1(x...) = f1(x[2])
    end
    c = Any['c', 1]
    cats = categories(@snoopi_deep M.c1(c...))
    @test SnoopCompile.CalleeVararg ∉ cats
    @test SnoopCompile.CallerVararg ∈ cats
    @test SnoopCompile.UnspecCall ∈ cats
    SnoopCompile.show_suggest(io, cats, nothing, nothing)
    @test occursin(r"non-inferrable or unspecialized call with vararg caller.*annotate", String(take!(io)))

    # CalleeVararg
    M = Module()
    @eval M begin
        f2(x...) = 2*x[2]
        c2(x) = f2(x...)
    end
    cats = categories(@snoopi_deep M.c2(c))
    @test SnoopCompile.CallerVararg ∉ cats
    @test SnoopCompile.CalleeVararg ∈ cats
    @test SnoopCompile.UnspecCall ∈ cats
    SnoopCompile.show_suggest(io, cats, nothing, nothing)
    @test occursin(r"non-inferrable or unspecialized call with vararg callee.*annotate", String(take!(io)))

    # InvokeCalleeVararg
    M = Module()
    @eval M begin
        struct AType end
        struct BType end
        Base.show(io::IO, ::AType) = print(io, "A")
        Base.show(io::IO, ::BType) = print(io, "B")
        @noinline doprint(ref) = print(IOBuffer(), "a", ref[], 3.2)
    end
    tinf = @snoopi_deep M.doprint(Ref{Union{M.AType,M.BType}}(M.AType()))
    if !isempty(inference_triggers(tinf))
        cats = categories(tinf)
        @test cats == [SnoopCompile.FromTestCallee, SnoopCompile.InvokedCalleeVararg]
        SnoopCompile.show_suggest(io, cats, nothing, nothing)
        @test occursin(r"invoked callee is varargs.*homogenize", String(take!(io)))
    else
        @warn "Skipped InvokeCalleeVararg test due to improvements in inference"
    end

    # Vararg that resolves to a UnionAll
    M = Module()
    @eval M begin
        struct ArrayWrapper{T,N,A,Args} <: AbstractArray{T,N}
            data::A
            args::Args
        end
        ArrayWrapper{T}(data, args...) where T = ArrayWrapper{T,ndims(data),typeof(data),typeof(args)}(data, args)
        @noinline makewrapper(data::AbstractArray{T}, args) where T = ArrayWrapper{T}(data, args...)
    end
    # run and redefine for reproducible results
    M.makewrapper(rand(2,2), ["a", 'b', 5])
    M = Module()
    @eval M begin
        struct ArrayWrapper{T,N,A,Args} <: AbstractArray{T,N}
            data::A
            args::Args
        end
        ArrayWrapper{T}(data, args...) where T = ArrayWrapper{T,ndims(data),typeof(data),typeof(args)}(data, args)
        @noinline makewrapper(data::AbstractArray{T}, args) where T = ArrayWrapper{T}(data, args...)
    end
    tinf = @snoopi_deep M.makewrapper(rand(2,2), ["a", 'b', 5])
    itrigs = inference_triggers(tinf)
    @test length(itrigs) == 2
    s = suggest(itrigs[1])
    @test s.categories == [SnoopCompile.FromTestCallee, SnoopCompile.UnspecType]
    print(io, s)
    @test occursin("partial type call", String(take!(io)))
    s = suggest(itrigs[2])
    @test s.categories == [SnoopCompile.CallerVararg, SnoopCompile.UnspecType]
    print(io, s)
    @test occursin(r"partial type call with vararg caller.*ignore.*annotate", String(take!(io)))
    mtrigs = accumulate_by_source(Method, itrigs)
    for mtrig in mtrigs
        summary(io, mtrig)
    end
    str = String(take!(io))
    @test occursin("makewrapper(data", str)
    @test occursin("ArrayWrapper{Float64", str)
    @test occursin("Tuple{String", str)

    # ErrorPath
    M = Module()
    @eval M begin
        struct MyType end
        struct MyException <: Exception
            info::Vector{MyType}
        end
        MyException(obj::MyType) = MyException([obj])
        @noinline function checkstatus(b::Bool, info)
            if !b
                throw(MyException(info))
            end
            return nothing
        end
    end
    tinf = @snoopi_deep try M.checkstatus(false, M.MyType()) catch end
    if !isempty(inference_triggers(tinf))
        # Exceptions do not trigger a fresh entry into inference on Julia 1.8+
        cats = categories(tinf)
        @test cats == [SnoopCompile.FromTestCallee, SnoopCompile.ErrorPath]
        SnoopCompile.show_suggest(io, cats, nothing, nothing)
        @test occursin(r"error path.*ignore", String(take!(io)))
    end

    # Core.Box
    @test !SnoopCompile.hascorebox(AbstractVecOrMat{T} where T)   # test Union handling
    M = Module()
    @eval M begin
        struct MyInt <: Integer end
        Base.:(*)(::MyInt, r::Int) = 7*r
        function abmult(r::Int, z)  # from https://docs.julialang.org/en/v1/manual/performance-tips/#man-performance-captured
            if r < 0
                r = -r
            end
            f = x -> x * r
            return f(z)
        end
    end
    z = M.MyInt()
    tinf = @snoopi_deep M.abmult(3, z)
    itrigs = inference_triggers(tinf)
    itrig = only(itrigs)
    s = suggest(itrig)
    @test SnoopCompile.HasCoreBox ∈ s.categories
    print(io, s)
    @test occursin(r"Core\.Box.*fix this.*http", String(take!(io)))
    mtrigs = accumulate_by_source(Method, itrigs)
    summary(io, only(mtrigs))
    @test occursin(r"Core\.Box.*fix this.*http", String(take!(io)))

    # Test one called from toplevel
    fromtask() = (while false end; 1)
    tinf = @snoopi_deep wait(@async fromtask())
    @test isempty(staleinstances(tinf))
    itrigs = inference_triggers(tinf)
    itrig = only(itrigs)
    s = suggest(itrig)
    @test s.categories == [SnoopCompile.NoCaller]
    itree = trigger_tree(itrigs)
    print_tree(io, itree)
    @test occursin(r"{var\"#fromtask", String(take!(io)))
    print(io, s)
    occursin(r"unknown caller.*Task", String(take!(io)))
    mtrigs = accumulate_by_source(Method, itrigs)
    @test isempty(mtrigs)

    # Empty
    SnoopCompile.show_suggest(io, SnoopCompile.Suggestion[], nothing, nothing)
    @test occursin("Unspecialized or unknown for", String(take!(io)))

    # Printing says *something* for any set of categories
    annots = instances(SnoopCompile.Suggestion)
    iter = [1:2 for _ in 1:length(annots)]
    cats = SnoopCompile.Suggestion[]
    for state in Iterators.product(iter...)
        empty!(cats)
        for (i, s) in enumerate(state)
            if s == 2
                push!(cats, annots[i])
            end
        end
        SnoopCompile.show_suggest(io, cats, nothing, nothing)
        @test !isempty(String(take!(io)))
    end
end

@testset "flamegraph_export" begin
    M = Module()
    @eval M begin # Take another tinf
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end

    tinf = @snoopi_deep begin
        M.g(2)
    end
    @test isempty(staleinstances(tinf))
    frames = flatten(tinf; sortby=inclusive)

    fg = SnoopCompile.flamegraph(tinf)
    fgnodes = collect(AbstractTrees.PreOrderDFS(fg))
    for tgtname in (Base.VERSION < v"1.7" ? (:h, :i) : (:h, :i, :+))
        @test mapreduce(|, fgnodes; init=false) do node
            node.data.sf.linfo.def.name == tgtname
        end
    end
    # Test that the span covers the whole tree, and check for const-prop
    has_constprop = false
    for leaf in AbstractTrees.PreOrderDFS(fg)
        @test leaf.data.span.start in fg.data.span
        @test leaf.data.span.stop in fg.data.span
        has_constprop |= leaf.data.status & FlameGraphs.gc_event != 0x0
    end
    Base.VERSION >= v"1.7" && @test has_constprop

    frame1, frame2 = frames[1], frames[2]
    t1, t2 = inclusive(frame1), inclusive(frame2)
    # Ensure there's a tinf gap, and that cutting off the fastest-to-infer won't leave the tree headless
    if t1 != t2 && Method(frame1).name !== :g
        cutoff_bottom_frame = (t1 + t2) / 2
        fg2 = SnoopCompile.flamegraph(tinf, tmin = cutoff_bottom_frame)
        @test length(collect(AbstractTrees.PreOrderDFS(fg2))) == (length(collect(AbstractTrees.PreOrderDFS(fg))) - 1)
    end
    fg1 = flamegraph(tinf.children[1])
    @test endswith(string(fg.child.data.sf.func), ".g") && endswith(string(fg1.child.data.sf.func), ".h")
    fg2 = flamegraph(tinf.children[2])
    @test endswith(string(fg2.child.data.sf.func), ".i")

    # Printing
    M = Module()
    @eval M begin
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end
    tinf = @snoopi_deep begin
        M.g(2)
        M.g(true)
    end
    @test isempty(staleinstances(tinf))
    fg = SnoopCompile.flamegraph(tinf)
    @test endswith(string(fg.child.data.sf.func), ".g")
    counter = Dict{Method,Int}()
    visit(M) do item
        if isa(item, Core.MethodInstance)
            m = item.def
            if isa(m, Method)
                counter[m] = get(counter, m, 0) + 1
            end
            return false
        end
        return true
    end
    fg = SnoopCompile.flamegraph(tinf; mode=counter)
    @test endswith(string(fg.child.data.sf.func), ".g (2)")

    # Non-precompilability
    M = Module()
    @eval M begin
        struct MyFloat x::Float64 end
        Base.isless(x::MyFloat, y::Float64) = isless(x.x, y)
    end
    tinf = @snoopi_deep begin
        z = M.MyFloat(2.0)
        z < 3.0
    end
    fg = SnoopCompile.flamegraph(tinf)
    nonpc = false
    for leaf in AbstractTrees.PreOrderDFS(fg)
        nonpc |= leaf.data.sf.func === Symbol("Base.<") && leaf.data.status & FlameGraphs.runtime_dispatch != 0x0
    end
    @test nonpc
end

@testset "demos" begin
    # Just ensure they run
    @test SnoopCompile.itrigs_demo() isa SnoopCompile.InferenceTimingNode
    @test SnoopCompile.itrigs_higherorder_demo() isa SnoopCompile.InferenceTimingNode
end

include("testmodules/SnoopBench.jl")
@testset "parcel" begin
    a = SnoopBench.A()
    tinf = @snoopi_deep SnoopBench.f1(a)
    @test isempty(staleinstances(tinf))
    ttot, prs = SnoopCompile.parcel(tinf)
    mod, (tmod, tmis) = only(prs)
    @test mod === SnoopBench
    t, mi = only(tmis)
    @test ttot == tmod == t  # since there is only one
    @test mi.def.name === :f1
    ttot2, prs = SnoopCompile.parcel(tinf; tmin=10.0)
    @test isempty(prs)
    @test ttot2 == ttot

    tinf = @snoopi_deep begin
        fn = SnoopBench.sv()
        rm(fn)
    end
    ttot, prs = SnoopCompile.parcel(tinf.children[1].children[1])
    mod, (tmod, tmis) = only(prs)
    io = IOBuffer()
    SnoopCompile.write(io, tmis; tmin=0.0)
    str = String(take!(io))
    @test occursin("__lookup_kwbody__", str)
    SnoopCompile.write(io, tmis; tmin=0.0, has_bodyfunction=true)
    str = String(take!(io))
    @test !occursin("__lookup_kwbody__", str)

    A = [a]
    tinf = @snoopi_deep SnoopBench.mappushes(identity, A)
    @test isempty(staleinstances(tinf))
    ttot, prs = SnoopCompile.parcel(tinf)
    mod, (tmod, tmis) = only(prs)
    @test mod === SnoopBench
    @test ttot == tmod  # since there is only one
    @test length(tmis) == 2
    io = IOBuffer()
    SnoopCompile.write(io, tmis; tmin=0.0)
    str = String(take!(io))
    @test occursin(r"typeof\(mappushes\),Any,Vector\{A\}", str)
    @test occursin(r"typeof\(mappushes!\),typeof\(identity\),Vector\{Any\},Vector\{A\}", str)

    list = Any[1, 1.0, Float16(1.0), a]
    tinf = @snoopi_deep SnoopBench.mappushes(isequal(Int8(1)), list)
    @test isempty(staleinstances(tinf))
    ttot, prs = SnoopCompile.parcel(tinf)
    @test length(prs) == 2
    _, (tmodBase, tmis) = prs[findfirst(pr->pr.first === Base, prs)]
    tw, nw = SnoopCompile.write(io, tmis; tmin=0.0)
    @test 0.0 <= tw <= tmodBase * (1+10*eps())
    @test 0 <= nw <= length(tmis)
    str = String(take!(io))
    @test !occursin(r"Base.Fix2\{typeof\(isequal\).*SnoopBench.A\}", str)
    @test length(split(chomp(str), '\n')) == nw
    _, (tmodBench, tmis) = prs[findfirst(pr->pr.first === SnoopBench, prs)]
    @test sum(inclusive, tinf.children[1:end-1]) <= tmodBench + tmodBase # last child is not precompilable
    tw, nw = SnoopCompile.write(io, tmis; tmin=0.0)
    @test nw == 2
    str = String(take!(io))
    @test occursin(r"typeof\(mappushes\),Any,Vector\{Any\}", str)
    @test occursin(r"typeof\(mappushes!\),Base.Fix2\{typeof\(isequal\).*\},Vector\{Any\},Vector\{Any\}", str)

    td = joinpath(tempdir(), randstring(8))
    SnoopCompile.write(td, prs; tmin=0.0, ioreport=io)
    str = String(take!(io))
    @test occursin(r"Base: precompiled [\d\.]+ out of [\d\.]+", str)
    @test occursin(r"SnoopBench: precompiled [\d\.]+ out of [\d\.]+", str)
    file_base = joinpath(td, "precompile_Base.jl")
    @test isfile(file_base)
    @test occursin("ccall(:jl_generating_output", read(file_base, String))
    rm(td, recursive=true, force=true)
    SnoopCompile.write(td, prs; ioreport=io, header=false)
    str = String(take!(io))  # just to clear it in case we use it again
    @test !occursin("ccall(:jl_generating_output", read(file_base, String))
    rm(td, recursive=true, force=true)

    # issue #197
    f197(::Vector{T}) where T<:Integer = zero(T)
    g197(@nospecialize(x::Vector{<:Number})) = f197(x)
    g197([1,2,3])
    @test SnoopCompile.get_reprs([(rand(), mi) for mi in methodinstances(f197)])[1] isa AbstractSet
end

@testset "Specialization" begin
    Ts = subtypes(Any)
    tinf_unspec = @snoopi_deep SnoopBench.mappushes(SnoopBench.spell_unspec, Ts)
    tf_unspec = flatten(tinf_unspec)
    if Base.VERSION < v"1.8.0-DEV.1148"
        # To ensure independent data, invalidate all compiled CodeInstances
        mis = map(last, accumulate_by_source(MethodInstance, tf_unspec))
        for mi in mis
            SnoopCompile.isROOT(mi) && continue
            visit(mi) do item
                isa(item, Core.CodeInstance) || return true
                item.max_world = 0
                return true
            end
        end
    end
    tinf_spec = @snoopi_deep SnoopBench.mappushes(SnoopBench.spell_spec, Ts)
    tf_spec = flatten(tinf_spec)
    @test length(tf_unspec) < length(Ts) ÷ 5
    @test any(tmi -> occursin("spell_unspec(::Any)", repr(MethodInstance(tmi))), tf_unspec)
    @test length(tf_spec) >= length(Ts)
    @test !any(tmi -> occursin("spell_spec(::Any)", repr(MethodInstance(tmi))), tf_unspec)
    @test !any(tmi -> occursin("spell_spec(::Type)", repr(MethodInstance(tmi))), tf_unspec)

    # fig, axs = plt.subplots(1, 2)

    nruns = 10^3
    SnoopBench.mappushes(SnoopBench.spell_spec, Ts)
    @profile for i = 1:nruns
        SnoopBench.mappushes(SnoopBench.spell_spec, Ts)
    end
    rit = runtime_inferencetime(tinf_spec)
    @test !any(rit) do (ml, _)
        endswith(string(ml.file), ".c")   # attribute all costs to Julia code, not C code
    end
    m = @which SnoopBench.spell_spec(first(Ts))
    dspec = rit[findfirst(pr -> pr.first == m, rit)].second
    @test dspec.tinf > dspec.trun      # more time is spent on inference than on runtime
    @test dspec.nspec >= length(Ts)
    # Check that much of the time in `mappushes!` is spent on runtime dispatch
    mp = @which SnoopBench.mappushes!(SnoopBench.spell_spec, [], first(Ts))
    dmp = rit[findfirst(pr -> pr.first == mp, rit)].second
    @test dmp.trtd >= 0.5*dmp.trun
    # pgdsgui(axs[1], rit; bystr="Inclusive", consts=true, interactive=false)

    Profile.clear()
    SnoopBench.mappushes(SnoopBench.spell_unspec, Ts)
    @profile for i = 1:nruns
        SnoopBench.mappushes(SnoopBench.spell_unspec, Ts)
    end
    rit = runtime_inferencetime(tinf_unspec)
    m = @which SnoopBench.spell_unspec(first(Ts))
    dunspec = rit[findfirst(pr -> pr.first == m, rit)].second # trunspec, trdtunspec, tiunspec, nunspec
    @test dunspec.tinf < dspec.tinf/10
    @test dunspec.trun < 10*dspec.trun
    @test dunspec.nspec == 1
    # Test that no runtime dispatch occurs in mappushes!
    dmp = rit[findfirst(pr -> pr.first == mp, rit)].second
    @test dmp.trtd == 0
    # pgdsgui(axs[2], rit; bystr="Inclusive", consts=true, interactive=false)
end


@testset "Stale" begin
    cproj = Base.active_project()
    cd(joinpath("testmodules", "Stale")) do
        Pkg.activate(pwd())
        Pkg.precompile()
    end
    invalidations = @snoopr begin
        using StaleA, StaleC
        using StaleB
    end
    smis = filter(SnoopCompile.hasstaleinstance, methodinstances(StaleA))
    @test length(smis) == 2
    stalenames = [mi.def.name for mi in smis]
    @test :build_stale ∈ stalenames
    @test :use_stale ∈ stalenames
    trees = invalidation_trees(invalidations)
    tree = trees[findfirst(tree -> !isempty(tree.backedges), trees)]
    @test tree.method == which(StaleA.stale, (String,))   # defined in StaleC
    @test all(be -> Core.MethodInstance(be).def == which(StaleA.stale, (Any,)), tree.backedges)
    if Base.VERSION > v"1.8.0-DEV.368"
        tree = trees[findfirst(tree -> !isempty(tree.mt_backedges), trees)]
        @test only(tree.mt_backedges).first.def == which(StaleA.stale, (Any,))
        @test which(only(tree.mt_backedges).first.specTypes) == which(StaleA.stale, (String,))
        @test convert(Core.MethodInstance, only(tree.mt_backedges).second).def == which(StaleB.useA, ())
        tinf = @snoopi_deep begin
            StaleB.useA()
            StaleC.call_buildstale("hi")
        end
        @test isempty(SnoopCompile.StaleTree(first(smis).def, :noreason).backedges)  # constructor test
        healed = true
        if Base.VERSION < v"1.8"
            healed = false
            # On more recent Julia, the invalidation of StaleA.stale is "healed over" by re-inferrence
            # within StaleC. Hence we should skip this test.
            strees = precompile_blockers(invalidations, tinf)
            tree = only(strees)
            @test inclusive(tree) > 0
            @test tree.method == which(StaleA.stale, (String,))
            root, hits = only(tree.backedges)
            @test Core.MethodInstance(root).def == which(StaleA.stale, (Any,))
            @test Core.MethodInstance(only(hits)).def == which(StaleA.use_stale, (Vector{Any},))
        end
        # If we don't discount ones left in an invalidated state,
        # we get mt_backedges with a MethodInstance middle entry too
        strees2 = precompile_blockers(invalidations, tinf; min_world_exclude=0)
        sig, root, hits = only(only(strees2).mt_backedges)
        mi_stale = only(filter(mi -> endswith(String(mi.def.file), "StaleA.jl"), methodinstances(StaleA.stale, (String,))))
        @test sig == mi_stale
        @test convert(Core.MethodInstance, root) == Core.MethodInstance(only(hits)) == methodinstance(StaleB.useA, ())
        # What happens when we can't find it in the tree?
        idx = findfirst(isequal("jl_method_table_insert"), invalidations)
        pipe = Pipe()
        redirect_stdout(pipe) do
            broken_trees = invalidation_trees(invalidations[idx+1:end])
            @test isempty(precompile_blockers(broken_trees, tinf))
        end
        # IO
        io = IOBuffer()
        print(io, trees)
        @test occursin(r"stale\(x::String\) (in|@) StaleC.*formerly stale\(x\) (in|@) StaleA", String(take!(io)))
        if !healed
            print(io, strees)
            str = String(take!(io))
            @test occursin(r"inserting stale.* in StaleC.*invalidated:", str)
            @test occursin(r"blocked.*InferenceTimingNode: .*/.* on StaleA.use_stale", str)
            @test endswith(str, "\n]")
            print(IOContext(io, :compact=>true), strees)
            str = String(take!(io))
            @test endswith(str, ";]")
            SnoopCompile.printdata(io, [hits; hits])
            @test occursin("inclusive time for 2 nodes", String(take!(io)))
        end
        print(io, only(strees2))
        str = String(take!(io))
        @test occursin(r"inserting stale\(.* (in|@) StaleC.*invalidated:", str)
        @test occursin("mt_backedges", str)
        @test occursin(r"blocked.*InferenceTimingNode: .*/.* on StaleB.useA", str)
    end
    Pkg.activate(cproj)
end

_name(frame::SnoopCompileCore.InferenceTiming) = frame.mi_info.mi.def.name

@testset "reentrant concurrent profiles 1 - overlap" begin
    # Warmup
    @eval foo1(x) = x+2
    @eval foo1(2)

    # Test:
    t1 = SnoopCompileCore.start_deep_timing()

    @eval foo1(x) = x+2
    @eval foo1(2)

    t2 = SnoopCompileCore.start_deep_timing()

    @eval foo2(x) = x+2
    @eval foo2(2)

    SnoopCompileCore.stop_deep_timing!(t1)
    SnoopCompileCore.stop_deep_timing!(t2)

    prof1 = SnoopCompileCore.finish_snoopi_deep(t1)
    prof2 = SnoopCompileCore.finish_snoopi_deep(t2)

    @test Set(_name.(SnoopCompile.flatten(prof1))) == Set([:ROOT, :foo1, :foo2])
    @test Set(_name.(SnoopCompile.flatten(prof2))) == Set([:ROOT, :foo2])

    # Test Cleanup
    @test isempty(SnoopCompileCore.SnoopiDeepParallelism.invocations)
    @test isempty(Core.Compiler.Timings._timings[1].children)
end

@testset "reentrant concurrent profiles 2 - interleaved" begin
    # Warmup
    @eval foo1(x) = x+2
    @eval foo1(2)

    # Test:
    t1 = SnoopCompileCore.start_deep_timing()

    @eval foo1(x) = x+2
    @eval foo1(2)

    t2 = SnoopCompileCore.start_deep_timing()

    @eval foo2(x) = x+2
    @eval foo2(2)

    SnoopCompileCore.stop_deep_timing!(t1)

    @eval foo3(x) = x+2
    @eval foo3(2)

    SnoopCompileCore.stop_deep_timing!(t2)

    @eval foo4(x) = x+2
    @eval foo4(2)

    prof1 = SnoopCompileCore.finish_snoopi_deep(t1)

    @eval foo5(x) = x+2
    @eval foo5(2)

    prof2 = SnoopCompileCore.finish_snoopi_deep(t2)

    @test Set(_name.(SnoopCompile.flatten(prof1))) == Set([:ROOT, :foo1, :foo2])
    @test Set(_name.(SnoopCompile.flatten(prof2))) == Set([:ROOT, :foo2, :foo3])

    # Test Cleanup
    @test isempty(SnoopCompileCore.SnoopiDeepParallelism.invocations)
    @test isempty(Core.Compiler.Timings._timings[1].children)
end

@testset "reentrant concurrent profiles 3 - nested" begin
    # Warmup
    @eval foo1(x) = x+2
    @eval foo1(2)

    # Test:
    local prof1, prof2, prof3
    prof1 = SnoopCompileCore.@snoopi_deep begin
        @eval foo1(x) = x+2
        @eval foo1(2)
        prof2 = SnoopCompileCore.@snoopi_deep begin
            @eval foo2(x) = x+2
            @eval foo2(2)
            prof3 = SnoopCompileCore.@snoopi_deep begin
                @eval foo3(x) = x+2
                @eval foo3(2)
            end
            @eval foo4(x) = x+2
            @eval foo4(2)
        end
        @eval foo5(x) = x+2
        @eval foo5(2)
    end

    @test Set(_name.(SnoopCompile.flatten(prof1))) == Set([:ROOT, :foo1, :foo2, :foo3, :foo4, :foo5])
    @test Set(_name.(SnoopCompile.flatten(prof2))) == Set([:ROOT,        :foo2, :foo3, :foo4])
    @test Set(_name.(SnoopCompile.flatten(prof3))) == Set([:ROOT,               :foo3])

    # Test Cleanup
    @test isempty(SnoopCompileCore.SnoopiDeepParallelism.invocations)
    @test isempty(Core.Compiler.Timings._timings[1].children)
end

@testset "reentrant concurrent profiles 3 - parallelism + accurate timing" begin
    # Warmup
    @eval foo1(x) = x+2
    @eval foo1(2)

    # Test:
    local ts
    snoop_times = Float64[0.0, 0.0, 0.0, 0.0]
    # Run it twice to ensure we warmup the eval block
    for _ in 1:2
        @sync begin
            ts = [
                Threads.@spawn begin
                    sleep((i-1) / 10)  # (Divide by 10 so the test isn't too slow)
                    snoop_time = @timed SnoopCompile.@snoopi_deep @eval begin
                        $(Symbol("foo$i"))(x) = x + 1
                        sleep(1.5 / 10)
                        $(Symbol("foo$i"))(2)
                    end
                    snoop_times[i] = snoop_time.time
                    return snoop_time.value
                end
                for i in 1:4
            ]
        end
    end
    profs = fetch.(ts)

    @test Set(_name.(SnoopCompile.flatten(profs[1]))) == Set([:ROOT, :foo1])
    @test Set(_name.(SnoopCompile.flatten(profs[2]))) == Set([:ROOT, :foo1, :foo2])
    @test Set(_name.(SnoopCompile.flatten(profs[3]))) == Set([:ROOT,        :foo2, :foo3])
    @test Set(_name.(SnoopCompile.flatten(profs[4]))) == Set([:ROOT,               :foo3, :foo4])

    # Test the sanity of the reported Timings
    @testset for i in eachindex(profs)
        prof = profs[i]
        # Test that the time for the inference is accounted for
        @test 0.15 < prof.mi_timing.exclusive_time
        @test prof.mi_timing.exclusive_time < prof.mi_timing.inclusive_time
        # Test that the inclusive time (the total time reported by snoopi_deep) matches
        # the actual time to do the snoopi_deep, as measured by `@time`.
        # These should both be approximately ~0.15 seconds.
        @info prof.mi_timing.inclusive_time
        @test prof.mi_timing.inclusive_time <= snoop_times[i]
    end

    # Test Cleanup
    @test isempty(SnoopCompileCore.SnoopiDeepParallelism.invocations)
    @test isempty(Core.Compiler.Timings._timings[1].children)
end

if Base.VERSION >= v"1.7"
    @testset "JET integration" begin
        f(c) = sum(c[1])
        c = Any[Any[1,2,3]]
        tinf = @snoopi_deep f(c)
        rpt = SnoopCompile.JET.@report_call f(c)
        @test isempty(SnoopCompile.JET.get_reports(rpt))
        itrigs = inference_triggers(tinf)
        irpts = report_callees(itrigs)
        @test only(irpts).first == last(itrigs)
        @test !isempty(SnoopCompile.JET.get_reports(only(irpts).second))
        @test  isempty(SnoopCompile.JET.get_reports(report_caller(itrigs[end])))
    end
end
