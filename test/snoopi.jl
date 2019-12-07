using SnoopCompile
using Test

push!(LOAD_PATH, @__DIR__)
using A
using E
using FuncKinds
pop!(LOAD_PATH)

@testset "topmodule" begin
    # topmod is called on moduleroots but nevertheless this is a useful test
    @test SnoopCompile.topmodule([A, A.B]) === A
    @test SnoopCompile.topmodule([A, A.B.C]) === A
    @test SnoopCompile.topmodule([A.B, A]) === A
    @test SnoopCompile.topmodule([A.B.C, A]) === A
    @test SnoopCompile.topmodule([A.B.C, A.B.D]) === nothing
    @test SnoopCompile.topmodule([A, Base]) === A
    @test SnoopCompile.topmodule([Base, A]) === A
end

module Lookup
f1(x, y; a=1) = error("oops")
f2(f::Function, args...; kwargs...) = f1(args...; kwargs...)
end

@testset "lookup bodyfunction" begin
    Core.eval(Lookup, SnoopCompile.lookup_kwbody_ex)
    m = first(methods(Lookup.f1))
    f = Lookup.__lookup_kwbody__(m)
    @test occursin("f1#", String(nameof(f)))
    m = first(methods(Lookup.f2))
    f = Lookup.__lookup_kwbody__(m)
    isdefined(Core, :_apply_iterate) && @test f !== Core._apply_iterate
    @test f !== Core._apply
    @test occursin("f2#", String(nameof(f)))
end

uncompiled(x) = x + 1

@testset "snoopi" begin
    tinf = @snoopi uncompiled(2)
    @test any(td->td[2].def.name == :uncompiled, tinf)
    # Ensure older methods can be tested
    a = rand(Float16, 5)
    tinf = @snoopi sum(a)
    @test any(td->td[2].def.name == :sum, tinf)

    a = [E.ET(1)]
    c = [A.B.C.CT(1)]
    tinf = @snoopi (A.f(a); A.f(c))
    @test length(tinf) == 2

    pc = SnoopCompile.parcel(tinf)
    @test isa(pc, Dict)
    @test length(pc) == 1
    @test length(pc[:A]) == 1
    directive = pc[:A][1]
    @test occursin("C.CT", directive)
    @test !occursin("E.ET", directive)

    # Identify kwfuncs, whose naming depends on the Julia version (issue #46)
    # Also check for kw body functions (also tested below)
    tinf = @snoopi sortperm(rand(5); rev=true)
    pc = SnoopCompile.parcel(tinf)
    FK = pc[:Base]
    @test any(str->occursin("kwftype", str), FK)
    if VERSION >= v"1.4.0-DEV.215"
        @test any(str->occursin("__lookup_kwbody__", str), FK)
    else
        @test any(str->occursin("isdefined", str), FK)
    end

    # Keyword body functions
    tinf = @snoopi FuncKinds.callhaskw()
    pc = SnoopCompile.parcel(tinf)
    FK = pc[:FuncKinds]
    @test any(str->occursin("kwftype", str), FK)
    @test any(str->occursin("precompile(Tuple{typeof(FuncKinds.haskw),", str), FK)
    if VERSION >= v"1.4.0-DEV.215"
        @test any(str->occursin("let", str), FK)
        @test !any(str->occursin("isdefined", str), FK)
    else
        @test any(str->occursin("isdefined", str), FK)
    end

    # Wrap anonymous functions in an `if isdefined`
    list = Any["xbar7", "yfoo8"]
    tinf = @snoopi FuncKinds.hasfoo(list)
    pc = SnoopCompile.parcel(tinf)
    @test any(str->occursin("isdefined", str), pc[:FuncKinds])

    # Extract the generator in a name-independent manner
    tinf = @snoopi begin
        FuncKinds.gen(1.0f0)
        FuncKinds.gen2(3, 1.1)
        FuncKinds.genkw1()
        FuncKinds.genkw2(; b="hello")
    end
    pc = SnoopCompile.parcel(tinf)
    FK = pc[:FuncKinds]
    @test any(str->occursin("precompile(Tuple{typeof(FuncKinds.gen),Float32})", str), FK)
    @test any(str->occursin("precompile(Tuple{typeof(FuncKinds.gen2),$Int,Float64})", str), FK)
    @test any(str->occursin("typeof(which(FuncKinds.gen2,($Int,Any,)).generator.gen)", str), FK)
    @test any(str->occursin("precompile(Tuple{typeof(FuncKinds.genkw1)})", str), FK)
    @test !any(str->occursin("precompile(Tuple{typeof(FuncKinds.genkw2)})", str), FK)
    @test any(str->occursin("Tuple{Core.kwftype(typeof(FuncKinds.genkw2)),NamedTuple{(:b,),Tuple{String}},typeof(FuncKinds.genkw2)}", str), FK)
    if VERSION >=  v"1.4.0-DEV.215"
        @test any(str->occursin("__lookup_kwbody__(which(FuncKinds.genkw1, ()))", str), FK)
        @test any(str->occursin("__lookup_kwbody__(which(FuncKinds.genkw2, ()))", str), FK)
    else
        @test any(str->occursin("isdefined", str), FK)
    end

    # Inner functions
    tinf = @snoopi FuncKinds.hasinner(1, 2)
    pc = SnoopCompile.parcel(tinf)
    FK = pc[:FuncKinds]
    @test any(str->match(r"isdefined.*#inner#", str) !== nothing, FK)
end

@testset "Lots of methods" begin
    # Tests functions from JuliaInterpreter/test/toplevel_script.jl and LoweredCodeUtils
    tinf = @snoopi begin
        FuncKinds.f1(0)
        FuncKinds.f1(0.0)
        FuncKinds.f1(0.0f0)
        FuncKinds.f2("hi")
        FuncKinds.f2(UInt16(1))
        FuncKinds.f2(3.2)
        FuncKinds.f2(view([1,2], 1:1))
        FuncKinds.f2([1,2])
        FuncKinds.f2(reshape(view([1,2], 1:2), 2, 1))
        FuncKinds.f3(1, 1)
        FuncKinds.f3(1, :hi)
        FuncKinds.f3(UInt16(1), :hi)
        FuncKinds.f3(rand(2, 2), :hi, :there)
        FuncKinds.f4(1, 1)
        FuncKinds.f4(1)
        FuncKinds.f4(UInt(1), "hey", 2)
        FuncKinds.f4(rand(2,2))
        FuncKinds.f5(Int8(1); y=22)
        FuncKinds.f5(Int16(1))
        FuncKinds.f5(Int32(1))
        FuncKinds.f5(rand(2,2); y=7)
        FuncKinds.f6(1; z=8)
    end
    pc = SnoopCompile.parcel(tinf)
    FK = pc[:FuncKinds]
    @test any(str->occursin("typeof(FuncKinds.f1),Int", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f1),Float64", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f1),Float32", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f2),String", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f2),UInt16", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f2),Float64", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f2),$(typeof(view([1,2], 1:1)))", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f2),Array{$Int,1}", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f2),$(typeof(reshape(view([1,2], 1:2), 2, 1)))", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f3),$Int,$Int", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f3),$Int,Symbol", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f3),UInt16,Symbol", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f3),Array{Float64,2},Symbol,Symbol", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f4),$Int,$Int", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f4),$UInt,String", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f4),Array{Float64,2}", str), FK)
    @test any(str->occursin(r"kwftype\(typeof\(FuncKinds.f5.*:y.*Int8", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f5),Int16", str), FK)
    @test any(str->occursin("typeof(FuncKinds.f5),Int32", str), FK)
    @test any(str->occursin(r"kwftype\(typeof\(FuncKinds.f5.*:y.*Array\{Float64,2\}", str), FK)
    # @test any(str->occursin("typeof(FuncKinds.f6),(1, "hi"; z=8) == 1
    # @test any(str->occursin("typeof(FuncKinds.f7),(1, (1, :hi)) == 1
    # @test any(str->occursin("typeof(FuncKinds.f8),(0) == 1
    # @test any(str->occursin("typeof(FuncKinds.f9),(3) == 9
    # @test any(str->occursin("typeof(FuncKinds.f9),(3.0) == 3.0

end

@testset "@snoopi docs" begin
    # docstring is present (weird Docs bug)
    dct = Docs.meta(SnoopCompile)
    @test haskey(dct, Docs.Binding(SnoopCompile, Symbol("@snoopi")))
end
