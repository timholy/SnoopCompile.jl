using SnoopCompile
using JLD
using SparseArrays
using Test

push!(LOAD_PATH, @__DIR__)
using A
using E
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

uncompiled(x) = x + 1
@static if VERSION >= v"1.2.0-DEV.573"

    @testset "snoopi" begin
        timing_data = @snoopi uncompiled(2)
        @test any(td->td[2].def.name == :uncompiled, timing_data)
        # Ensure older methods can be tested
        a = rand(Float16, 5)
        timing_data = @snoopi sum(a)
        @test any(td->td[2].def.name == :sum, timing_data)

        a = [E.ET(1)]
        c = [A.B.C.CT(1)]
        timing_data = @snoopi (A.f(a); A.f(c))
        @test length(timing_data) == 2

        pc = SnoopCompile.parcel(timing_data)
        @test isa(pc, Dict)
        @test length(pc) == 1
        @test length(pc[:A]) == 1
        directive = pc[:A][1]
        @test occursin("C.CT", directive)
        @test !occursin("E.ET", directive)
    end

    # docstring is present (weird Docs bug)
    dct = Docs.meta(SnoopCompile)
    @test haskey(dct, Docs.Binding(SnoopCompile, Symbol("@snoopi")))
end

# issue #26
@snoopc "/tmp/anon.log" begin
    map(x->x^2, [1,2,3])
end
data = SnoopCompile.read("/tmp/anon.log")
pc = SnoopCompile.parcel(reverse!(data[2]))
@test length(pc[:Base]) <= 1

# issue #29
keep, pcstring, topmod, name = SnoopCompile.parse_call("Tuple{getfield(JLD, Symbol(\"##s27#8\")), Any, Any, Any, Any, Any}")
@test keep
@test pcstring == "Tuple{getfield(JLD, Symbol(\"##s27#8\")), Int, Int, Int, Int, Int}"
@test topmod == :JLD
@test name == "##s27#8"
save("/tmp/mat.jld", "mat", sprand(10, 10, 0.1))
@snoopc "/tmp/jldanon.log" begin
    using JLD, SparseArrays
    mat = load("/tmp/mat.jld", "mat")
end
data = SnoopCompile.read("/tmp/jldanon.log")
pc = SnoopCompile.parcel(reverse!(data[2]))
@test any(startswith.(pc[:JLD], "isdefined"))

#=
# Simple call
let str = "sum"
    keep, pcstring, topmod = SnoopCompile.parse_call("Foo.any($str)")
    @test keep
    @test pcstring == "Tuple{$str}"
    @test topmod == :Main
end

# Operator
let str = "Base.:*, Int, Int"
    keep, pcstring, topmod = SnoopCompile.parse_call("Foo.any($str)")
    @test keep
    @test pcstring == "Tuple{$str}"
    @test topmod == :Base
end

# Function as argument
let str = "typeof(Base.identity), Array{Bool, 1}"
    keep, pcstring, topmod = SnoopCompile.parse_call("Foo.any($str, Vararg{Any, N} where N)")
    @test keep
    @test pcstring == "Tuple{$str, Int}"
    @test topmod == :Base
end

# Anonymous function closure in a new module as argument
let func = (@eval Main module SnoopTestTemp
            func = () -> (y = 2; (x -> x > y))
        end).func
    str = "getfield(SnoopTestTemp, Symbol(\"$(typeof(func()))\")), Array{Float32, 1}"
    keep, pcstring, topmod = SnoopCompile.parse_call("Foo.any($str)")
    @test keep
    @test pcstring == "Tuple{$str}"
    @test topmod == :SnoopTestTemp
end

# Function as a type
let str = "typeof(Base.Sort.sort!), Array{Any, 1}, Base.Sort.MergeSortAlg, Base.Order.By{typeof(Base.string)}"
    keep, pcstring, topmod = SnoopCompile.parse_call("Foo.Bar.sort!($str)")
    @test keep
    @test pcstring == "Tuple{$str}"
    @test topmod == :Base
end
=#
@static if VERSION >= v"1.2.0-DEV.573"
    @testset "timesum" begin
        loadSnoop = SnoopCompile.@snoopi using LinearAlgebra
        @test typeof(timesum(loadSnoop)) == Float64
    end
end

include("colortypes.jl")
