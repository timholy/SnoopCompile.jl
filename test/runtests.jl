using SnoopCompile
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
