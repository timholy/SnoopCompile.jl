using Test

if Base.VERSION >= v"1.7"
    import JET
    import Cthulhu
end

if VERSION >= v"1.6.0-DEV.1190"  # https://github.com/JuliaLang/julia/pull/37749
    @testset "snoopi_deep" begin
        include("snoopi_deep.jl")
    end
end

if VERSION >= v"1.6.0-DEV.1192"  # https://github.com/JuliaLang/julia/pull/37136
    @testset "snoopl" begin
        include("snoopl.jl")
    end
end

if VERSION >= v"1.2.0-DEV.573"
    include("snoopi.jl")
end

using SnoopCompile

if isdefined(SnoopCompile, :invalidation_trees)
    include("snoopr.jl")
end

@testset "Miscellaneous" begin
# issue #26
logfile = joinpath(tempdir(), "anon.log")
@snoopc logfile begin
    map(x->x^2, [1,2,3])
end
data = SnoopCompile.read(logfile)
pc = SnoopCompile.parcel(reverse!(data[2]))
@test_broken length(pc[:Base]) <= 1

# issue #29
keep, pcstring, topmod, name = SnoopCompile.parse_call("Tuple{getfield(JLD, Symbol(\"##s27#8\")), Any, Any, Any, Any, Any}")
@test keep
@test pcstring == "Tuple{getfield(JLD, Symbol(\"##s27#8\")), Int, Int, Int, Int, Int}"
@test topmod == :JLD
@test name == "##s27#8"
logfile = joinpath(tempdir(), "isdefined.log")
@snoopc logfile begin
    @eval module IsDef
        @generated function tm(x)
            return :(typemax($x))
        end
    end
    IsDef.tm(1)
end
data = SnoopCompile.read(logfile)
pc = SnoopCompile.parcel(reverse!(data[2]))
@test any(startswith.(pc[:IsDef], "isdefined"))

if Base.VERSION < v"1.7.0-DEV.694"
    @testset "Warning for failures to precompile" begin
        pcs = ["@warnpcfail precompile(fsimple, (Char,))",
            "@warnpcfail precompile(fsimple, (Char, Char))",
            "@warnpcfail precompile(fsimple, (Char, Char, Char))",
        ]
        fn = tempname() * ".jl"
        open(fn, "w") do io
            println(io, "fsimple(x, y) = 1")
            SnoopCompile.write(io, pcs; writewarnpcfail=true)
        end
        @test_logs (:warn, r"precompile\(fsimple, \(Char,\)\)") (:warn, r"precompile\(fsimple, \(Char, Char, Char\)\)") include(fn)
        rm(fn)
    end
end

# coverage
if isdefined(SnoopCompile.SnoopCompileCore, Symbol("@snoopi_deep"))
    tinf = SnoopCompile.flatten_demo()
    @test length(accumulate_by_source(flatten(tinf))) == 7
end

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

