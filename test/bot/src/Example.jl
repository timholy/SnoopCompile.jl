module Example
export hello, domath

"""
    hello(who::String)

Return "Hello, `who`".
"""
hello(who::String) = "Hello, $who"

"""
    domath(x::Number)

Return `x + 5`.
"""
domath(x::Number) = x + 5

include("../deps/SnoopCompile/precompile/precompile_Example.jl")
_precompile_()

end
