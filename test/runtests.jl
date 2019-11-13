using SnoopCompile
using JLD
using SparseArrays
using Test

uncompiled(x) = x + 1
if VERSION >= v"1.2.0-DEV.573"
    include_string(Main, """
    @testset "snoopi" begin
        timing_data = @snoopi uncompiled(2)
        @test any(td->td[2].def.name == :uncompiled, timing_data)
        # Ensure older methods can be tested
        a = rand(Float16, 5)
        timing_data = @snoopi sum(a)
        @test any(td->td[2].def.name == :sum, timing_data)
    end
    """)
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
@test keep == true
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

include("colortypes.jl")
