using SnoopCompile
using Test

const SP = VERSION >= v"1.6.0-DEV.771" ? " " : "" # JuliaLang/julia #37085

push!(LOAD_PATH, joinpath(@__DIR__, "testmodules"))
using A
using E
using FuncKinds
using Reachable.ModuleA
using Reachable.ModuleB
using Reachable2
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

@testset "known_type" begin
    @eval module OtherModule
        p() = 1
        q() = 1
    end
    @eval module KnownType
        f() = 1
        module SubModule
            g() = 1
            h() = 1
        end
        module Exports
            export i
            i() = 1
            j() = 1
        end
        using .SubModule: g
        using .Exports
        using Main.OtherModule: p
    end
    @test  SnoopCompile.known_type(KnownType, which(KnownType.f, ()).sig)
    @test  SnoopCompile.known_type(KnownType, which(KnownType.g, ()).sig)
    @test  SnoopCompile.known_type(KnownType, which(KnownType.SubModule.g, ()).sig)
    @test  SnoopCompile.known_type(KnownType, which(KnownType.SubModule.h, ()).sig)  # it's reachable if appropriately qualified
    @test  SnoopCompile.known_type(KnownType, which(KnownType.i, ()).sig)
    @test  SnoopCompile.known_type(KnownType, which(KnownType.Exports.i, ()).sig)
    @test  SnoopCompile.known_type(KnownType, which(KnownType.Exports.j, ()).sig)    # it's reachable if appropriately qualified
    @test  SnoopCompile.known_type(KnownType, which(OtherModule.p, ()).sig)
    @test !SnoopCompile.known_type(KnownType, which(OtherModule.q, ()).sig)
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
    tinf = @snoopi begin
        FuncKinds.fsort()
        FuncKinds.fsort2()
        FuncKinds.fsort3()
    end
    pc = SnoopCompile.parcel(tinf)
    FK = pc[:Base]
    @test  any(str->occursin("kwftype", str), FK)
    @test !any(str->occursin(r"Type\{NamedTuple.*typeof\(sin\)", str), FK)
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
    @test any(str->occursin("precompile(Tuple{typeof(haskw),", str), FK)
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
    @test any(str->occursin("precompile(Tuple{typeof(gen),Float32})", str), FK)
    @test any(str->occursin("precompile(Tuple{typeof(gen2),$Int,Float64})", str), FK)
    @test any(str->occursin("typeof(which(gen2,($Int,Any,)).generator.gen)", str), FK)
    @test any(str->occursin("precompile(Tuple{typeof(genkw1)})", str), FK)
    @test !any(str->occursin("precompile(Tuple{typeof(genkw2)})", str), FK)
    @test any(str->occursin("Tuple{Core.kwftype(typeof(genkw2)),NamedTuple{(:b,),$(SP)Tuple{String}},typeof(genkw2)}", str), FK)
    if VERSION >=  v"1.4.0-DEV.215"
        @test any(str->occursin("__lookup_kwbody__(which(genkw1, ()))", str), FK)
        @test any(str->occursin("__lookup_kwbody__(which(genkw2, ()))", str), FK)
    else
        @test any(str->occursin("isdefined", str), FK)
    end

    # Inner functions
    tinf = @snoopi FuncKinds.hasinner(1, 2)
    pc = SnoopCompile.parcel(tinf)
    FK = pc[:FuncKinds]
    @test any(str->match(r"isdefined.*#inner#", str) !== nothing, FK)

    # exclusions_remover
    exclusions = ["hi", "bye"]
    pcI = Set(["good", "bad", "hi", "bye", "no"])
    @test SnoopCompile.exclusions_remover!(pcI, exclusions) == Set(["good", "bad", "no"])
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
    @test any(str->occursin("typeof(f1),Int", str), FK)
    @test any(str->occursin("typeof(f1),Float64", str), FK)
    @test any(str->occursin("typeof(f1),Float32", str), FK)
    @test any(str->occursin("typeof(f2),String", str), FK)
    @test any(str->occursin("typeof(f2),UInt16", str), FK)
    @test any(str->occursin("typeof(f2),Float64", str), FK)
    @test any(str->occursin("typeof(f2),$(typeof(view([1,2], 1:1)))", str), FK)
    @test any(str->occursin("typeof(f2),$(Vector{Int})", str), FK)
    @test any(str->occursin("typeof(f2),$(typeof(reshape(view([1,2], 1:2), 2, 1)))", str), FK)
    @test any(str->occursin("typeof(f3),$Int,$Int", str), FK)
    @test any(str->occursin("typeof(f3),$Int,Symbol", str), FK)
    @test any(str->occursin("typeof(f3),UInt16,Symbol", str), FK)
    @test any(str->occursin("typeof(f3),$(Matrix{Float64}),Symbol,Symbol", str), FK)
    @test any(str->occursin("typeof(f4),$Int,$Int", str), FK)
    @test any(str->occursin("typeof(f4),$UInt,String", str), FK)
    @test any(str->occursin("typeof(f4),$(Matrix{Float64})", str), FK)
    @test any(str->occursin(r"kwftype\(typeof\(f5.*:y.*Int8", str), FK)
    @test any(str->occursin("typeof(f5),Int16", str), FK)
    @test any(str->occursin("typeof(f5),Int32", str), FK)
    if "$(Matrix{Float64})" == "Matrix{Float64}"
        @test any(str->occursin(r"kwftype\(typeof\(f5.*:y.*Matrix\{Float64\}", str), FK)
    else
        @test any(str->occursin(r"kwftype\(typeof\(f5.*:y.*Array\{Float64,2\}", str), FK)
    end
    # @test any(str->occursin("typeof(f6),(1, "hi"; z=8) == 1
    # @test any(str->occursin("typeof(f7),(1, (1, :hi)) == 1
    # @test any(str->occursin("typeof(f8),(0) == 1
    # @test any(str->occursin("typeof(f9),(3) == 9
    # @test any(str->occursin("typeof(f9),(3.0) == 3.0

end

# Issue https://github.com/timholy/SnoopCompile.jl/issues/40#issuecomment-570560584
@testset "Reachable" begin
    tinf = @snoopi begin
        include("snoopreachable.jl")
    end
    pc = SnoopCompile.parcel(tinf)
    pcd = pc[:Reachable]
    @test length(pcd) == 2
    @test sum(str->occursin("RchA", str), pcd) == 2
    # Make sure that two modues that know about each other only via Main do not allow precompilation
    @test !any(str->occursin("ModuleB.f", str), pcd)
    pcd = pc[:Reachable2]
    @test length(pcd) == 1
end

@testset "@snoopi docs" begin
    # docstring is present (weird Docs bug)
    dct = Docs.meta(SnoopCompile.SnoopCompileCore)
    @test haskey(dct, Docs.Binding(SnoopCompile.SnoopCompileCore, Symbol("@snoopi")))
end

@testset "Duplicates (#70)" begin
    tinf = @snoopi begin
        function eval_local_function(i)
            @eval generated() = $i
            return Base.invokelatest(generated)
        end
        eval_local_function(1)
        eval_local_function(2)
        eval_local_function(3)
    end
    pc = SnoopCompile.parcel(tinf, remove_exclusions = false)
    @test count(isequal("Base.precompile(Tuple{typeof(generated)})"), pc[:Main]) == 1
end
